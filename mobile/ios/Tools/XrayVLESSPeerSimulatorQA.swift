// Dedicated standalone synthetic peer lab, never a production target.
import Darwin
import Foundation
import LibXray
#if APL_TUN_PAIR_QA && targetEnvironment(simulator)
import tun2proxy
#endif

@main
struct XrayVLESSPeerSimulatorQA {
    private static func invokeJSON(_ request: Data) -> Data? {
        guard let json = String(data: request, encoding: .utf8),
              let input = strdup(json) else { return nil }
        defer { free(input) }
        guard let reply = CGoInvoke(input) else { return nil }
        defer { CGoFree(reply) }
        let length = strnlen(reply, XrayVLESSRuntimeConfig.maxResponseBytes + 1)
        guard length <= XrayVLESSRuntimeConfig.maxResponseBytes else { return nil }
        return Data(bytes: reply, count: length)
    }

    private static func invoke(_ method: String, config: String? = nil) -> [String: Any]? {
        var request: [String: Any] = ["apiVersion": 3, "method": method]
        if let config { request["payload"] = ["xrayJson": config] }
        guard let bytes = try? JSONSerialization.data(withJSONObject: request),
              let reply = invokeJSON(bytes),
              let result = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              result["success"] as? Bool == true else { return nil }
        return result
    }

    private static func running() -> Bool? {
        (invoke("getXrayState")?["data"] as? [String: Any])?["running"] as? Bool
    }

    private static func socketAt(_ port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { close(fd); return nil }
        return fd
    }

    private static func closed(_ port: UInt16) -> Bool {
        if let fd = socketAt(port) { close(fd); return false }
        return true
    }

    private static func hasExited(_ semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now()) == .success
    }

    private static func fail(_ stage: String) -> Never {
        _ = invoke("stopXray")
        print("PEER_QA_FAILED_" + stage); exit(1)
    }

    static func main() async {
#if targetEnvironment(simulator) || os(macOS)
        let args = CommandLine.arguments
        guard args.count == 4,
              ["server", "client", "tun-client"].contains(args[1]),
              let port = UInt16(args[3]), (39879...39884).contains(port),
              closed(port),
              (invoke("xrayVersion")?["data"] as? [String: Any])?["version"] as? String == "26.11.9",
              running() == false else { fail("PRECHECK") }
#if os(macOS)
        guard args[1] == "server" else { fail("MAC_SERVER_ONLY") }
#endif
        let config: String
        do {
            let path = URL(fileURLWithPath: args[2])
            let raw = try Data(contentsOf: path)
            guard raw.count <= 16384 else { fail("INPUT") }
            if args[1] == "server" {
                guard let text = String(data: raw, encoding: .utf8) else { fail("INPUT") }
                config = text
            } else {
                guard let text = String(data: raw, encoding: .utf8) else { fail("INPUT") }
                let candidate = try VLESSRealityShareLink.parse(text)
                guard candidate.serverHost == "127.0.0.1", candidate.serverPort == 39882,
                      let converted = invokeJSON(try candidate.conversionRequest()) else {
                    fail("CLIENT_CONVERSION")
                }
                let bytes = try XrayVLESSRuntimeConfig.prepare(candidate: candidate,
                    converterResponse: converted, socksPort: Int(port))
                guard let text = String(data: bytes, encoding: .utf8) else { fail("CLIENT_CONFIG") }
                config = text
            }
        } catch { fail("CONFIG") }
        guard invoke("testXray", config: config) != nil else { fail("TEST_XRAY") }
        guard invoke("runXray", config: config) != nil, running() == true else { fail("RUN") }
#if APL_TUN_PAIR_QA && targetEnvironment(simulator)
        if args[1] == "tun-client" {
            let path = (try? String(contentsOfFile: args[2] + ".path", encoding: .utf8)) ?? ""
            var fds: [Int32] = [-1,-1]
            guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &fds) == 0 else { fail("SOCKETPAIR") }
            let rawFD = fds[0], injectionFD = fds[1]
            let plan: XraySocksHandoffPlan
            do {
                plan = try XraySocksHandoffPlan.prepare(tunFD:Int(rawFD),socksPort:Int(port),dnsBypass:[])
            } catch { fail("TUN_PLAN") }
            let queue = DispatchQueue(label:"apl.qa.private.tun")
            let exited = DispatchSemaphore(value:0)
            let arguments = plan.tun2proxyArguments
            queue.async {
                let code = arguments.withCString { tun2proxy_run_with_cli_args($0,1500,true) }
                print("TUN_QA_RUST_EXIT_\(code)")
                fflush(stdout)
                exited.signal()
            }
            try? await Task.sleep(nanoseconds:250_000_000)
            guard !hasExited(exited) else { fail("RUST_EARLY_EXIT") }
            let result = XrayTunPacketQA.probe(fd:injectionFD,path:path)
            guard !hasExited(exited) else { fail("RUST_UNSOLICITED_EXIT") }
            do {
                try await TunnelEngineHandoff.stopAndDrain(engineQueue:queue,timeout:5) {
                    _ = tun2proxy_stop()
                }
            } catch { fail("RUST_DRAIN") }
            guard hasExited(exited),
                  fcntl(rawFD,F_GETFD) != -1 else { fail("RUST_DRAIN_OR_FD") }
            close(rawFD); close(injectionFD)
            print("TUN_QA_RUST_DRAINED_DESCRIPTOR_CLOSED")
            guard invoke("stopXray") != nil, running() == false, closed(port) else { fail("STOP_XRAY") }
            var usage = rusage()
            if getrusage(RUSAGE_SELF,&usage) == 0 {
                print("TUN_QA_PEAK_RSS_BYTES_\(usage.ru_maxrss)")
            }
            print("TUN_QA_RECEIPT_\(result)")
            print("PEER_QA_STOPPED_tun-client"); fflush(stdout)
            return
        }
#endif
        guard args[1] != "tun-client" else { fail("TUN_NOT_COMPILED") }
        print("PEER_QA_READY_" + args[1]); fflush(stdout)
        // Bounded lifetime even if host orchestration is interrupted.
        let deadline = DispatchTime.now() + .seconds(args[1] == "server" ? 75 : 18)
        while DispatchTime.now() < deadline &&
            !FileManager.default.fileExists(atPath: args[2] + ".stop") {
            try? await Task.sleep(nanoseconds:50_000_000)
        }
        guard invoke("stopXray") != nil, running() == false, closed(port) else {
            fail("STOP")
        }
        print("PEER_QA_STOPPED_" + args[1]); fflush(stdout)
#else
        print("REFUSE_PHYSICAL_DEVICE"); exit(20)
#endif
    }
}
