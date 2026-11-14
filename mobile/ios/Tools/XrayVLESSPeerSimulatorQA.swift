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
        print("PEER_QA_FAILED_" + stage); fflush(stdout)
        _ = invoke("stopXray")
        exit(1)
    }

#if APL_TUN_PAIR_QA && targetEnvironment(simulator)
    private static func tunCycle(config: String, port: UInt16, path: String,
                                 lifecycle: inout XrayHandoffLifecycle, probeKind: String = "tcp4") async -> Bool {
        print("TUN_QA_XRAY_START_BEGIN"); fflush(stdout)
        guard running() == false, closed(port),
              let token = try? lifecycle.begin(),
              invoke("runXray", config:config) != nil, running() == true else { fail("CYCLE_START") }
        print("TUN_QA_XRAY_START_COMPLETE"); fflush(stdout)
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
            print("TUN_QA_RUST_START_BEGIN"); fflush(stdout)
            queue.async {
                let code = arguments.withCString { tun2proxy_run_with_cli_args($0,1500,true) }
                print("TUN_QA_RUST_EXIT_\(code)")
                fflush(stdout)
                exited.signal()
            }
            try? await Task.sleep(nanoseconds:250_000_000)
            print("TUN_QA_RUST_START_WAIT_COMPLETE"); fflush(stdout)
            guard !hasExited(exited) else { fail("RUST_EARLY_EXIT") }
            guard (try? lifecycle.ready(generation: token)) != nil else { fail("STATE_READY") }
            let result: Bool
            switch probeKind {
            case "udp4": result = XrayTunPacketQA.probeUDP(fd:injectionFD,path:path,v6:false)
            case "udp6": result = XrayTunPacketQA.probeUDP(fd:injectionFD,path:path,v6:true)
            case "tcp6": result = XrayTunPacketQA.probe(fd:injectionFD,path:path,v6:true)
            default: result = XrayTunPacketQA.probe(fd:injectionFD,path:path)
            }
            guard !hasExited(exited) else { fail("RUST_UNSOLICITED_EXIT") }
            guard (try? lifecycle.requestStop(generation: token)) == true else { fail("STATE_STOP") }
            do {
                try await TunnelEngineHandoff.stopAndDrain(engineQueue:queue,timeout:5) {
                    _ = tun2proxy_stop()
                }
            } catch { fail("RUST_DRAIN") }
            guard hasExited(exited),
                  fcntl(rawFD,F_GETFD) != -1 else { fail("RUST_DRAIN_OR_FD") }
            close(rawFD); close(injectionFD)
            guard fcntl(rawFD,F_GETFD) == -1, fcntl(injectionFD,F_GETFD) == -1,
                  (try? lifecycle.drained(generation:token)) != nil else { fail("STATE_DRAINED") }
            print("TUN_QA_RUST_DRAINED_DESCRIPTOR_CLOSED"); fflush(stdout)
            print("TUN_QA_XRAY_STOP_BEGIN"); fflush(stdout)
            guard invoke("stopXray") != nil, running() == false, closed(port) else { fail("STOP_XRAY") }
            print("TUN_QA_XRAY_STOP_COMPLETE"); fflush(stdout)
        return result
    }

    private static func resourceReceipt(_ cycle:Int) {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF,&usage) == 0 else { fail("RSS") }
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to:&info) {
            $0.withMemoryRebound(to:integer_t.self, capacity:Int(count)) {
                task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count)
            }
        }
        guard status == KERN_SUCCESS else { fail("TASK_INFO") }
        let limit = min(getdtablesize(),4096)
        var open = 0, sockets = 0, inet = 0, unix = 0, other = 0
        for fd in 0..<limit where fcntl(fd,F_GETFD) != -1 {
            open += 1
            var kind:Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            if getsockopt(fd,SOL_SOCKET,SO_TYPE,&kind,&len) == 0 {
                sockets += 1
                var address = sockaddr_storage()
                var size = socklen_t(MemoryLayout<sockaddr_storage>.size)
                if withUnsafeMutablePointer(to:&address, {
                    $0.withMemoryRebound(to:sockaddr.self,capacity:1) { getsockname(fd,$0,&size) }
                }) == 0 {
                    switch Int32(address.ss_family) {
                    case AF_INET, AF_INET6: inet += 1
                    case AF_UNIX: unix += 1
                    default: other += 1
                    }
                } else { other += 1 }
            }
        }
        print("TUN_QA_CYCLE_\(cycle)_RSS_\(info.resident_size)_PEAK_\(usage.ru_maxrss)_FD_SAMPLE_\(open)_SOCKETS_\(sockets)_INET_\(inet)_UNIX_\(unix)_OTHER_\(other)")
    }
#endif

    static func main() async {
#if targetEnvironment(simulator) || os(macOS)
        let args = CommandLine.arguments
        guard args.count == 4,
              ["server", "client", "tun-client", "tun-cycles", "wg-tun", "wg-dual", "wg-client"].contains(args[1]),
              let port = UInt16(args[3]), (39879...39884).contains(port),
              closed(port),
              (invoke("xrayVersion")?["data"] as? [String: Any])?["version"] as? String == "26.11.9",
              running() == false else { fail("PRECHECK") }
#if os(macOS)
        #if APL_PHYSICAL_PEER_PREFLIGHT
        guard args[1] == "server" || args[1] == "client" || args[1] == "wg-client" else { fail("MAC_SERVER_ONLY") }
#else
        guard args[1] == "server" else { fail("MAC_SERVER_ONLY") }
#endif
#endif
        let config: String
        do {
            let path = URL(fileURLWithPath: args[2])
            let raw = try Data(contentsOf: path)
            guard raw.count <= 16384 else { fail("INPUT") }
            if args[1] == "server" {
                guard let text = String(data: raw, encoding: .utf8) else { fail("INPUT") }
                config = text
            } else if args[1] == "wg-client" {
#if APL_PHYSICAL_PEER_PREFLIGHT && os(macOS)
                guard let text=String(data:raw,encoding:.utf8) else {fail("INPUT")}
                config=try XrayWireGuardLabConfig.prepare(text,port:Int(port),dual:true,physical:true)
#else
                fail("WG_PREFLIGHT_ONLY")
#endif
            } else if args[1] == "wg-tun" || args[1] == "wg-dual" {
                guard let text = String(data: raw, encoding: .utf8) else { fail("INPUT") }
                config = try XrayWireGuardLabConfig.prepare(text,port:Int(port),dual:args[1]=="wg-dual")
            } else {
                guard let text = String(data: raw, encoding: .utf8) else { fail("INPUT") }
                let candidate = try VLESSRealityShareLink.parse(text)
#if APL_PHYSICAL_PEER_PREFLIGHT && os(macOS)
                let allowedHost = candidate.serverHost == "192.168.1.80" || candidate.serverHost == "127.0.0.1"
#else
                let allowedHost = candidate.serverHost == "127.0.0.1"
#endif
                guard allowedHost, candidate.serverPort == 39882,
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
#if APL_TUN_PAIR_QA && targetEnvironment(simulator)
        if args[1] == "tun-client" || args[1] == "tun-cycles" || args[1] == "wg-tun" || args[1] == "wg-dual" {
            let raw = (try? String(contentsOfFile:args[2] + ".path", encoding:.utf8)) ?? ""
            let paths = raw.split(separator:"\n").map(String.init)
            let repeated = args[1] == "tun-cycles"
            let dual = args[1] == "wg-dual"
            guard paths.count == (repeated ? 12 : dual ? 3 : 1), Set(paths).count == paths.count else { fail("PATHS") }
            var lifecycle = XrayHandoffLifecycle()
            if repeated { resourceReceipt(0) }
            for (index,path) in paths.enumerated() {
                print("TUN_QA_BEGIN_CYCLE_\(index+1)"); fflush(stdout)
                let kind = dual ? ["udp4","udp6","tcp6"][index] : "tcp4"
                let result = await tunCycle(config:config,port:port,path:path,lifecycle:&lifecycle,probeKind:kind)
                if dual { print("TUN_QA_DUAL_"+kind+"_"+String(result)); fflush(stdout) }
                if repeated {
                    guard result, lifecycle.phase == .stopped, lifecycle.generation == UInt64(index+1) else { fail("CYCLE_RECEIPT") }
                    try? await Task.sleep(nanoseconds:400_000_000)
                    resourceReceipt(index+1)
                    print("TUN_QA_CYCLE_PASS_\(index+1)"); fflush(stdout)
                } else {
                    var usage = rusage()
                    if getrusage(RUSAGE_SELF,&usage) == 0 { print("TUN_QA_PEAK_RSS_BYTES_\(usage.ru_maxrss)") }
                    print("TUN_QA_RECEIPT_\(result)")
                }
            }
            if repeated {
                try? await Task.sleep(nanoseconds:3_000_000_000)
                resourceReceipt(13)
            }
            print("PEER_QA_STOPPED_" + args[1]); fflush(stdout)
            return
        }
#endif
        guard args[1] == "server" || args[1] == "client" || args[1] == "wg-client" else { fail("TUN_NOT_COMPILED") }
        guard invoke("runXray", config:config) != nil, running() == true else { fail("RUN") }
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
