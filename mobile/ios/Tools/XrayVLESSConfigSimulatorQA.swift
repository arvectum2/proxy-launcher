// Synthetic standalone lab. Never a production app/extension source.
import CryptoKit
import Darwin
import Foundation
import LibXray

@main
struct XrayVLESSConfigSimulatorQA {
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

    private static func socksGreeting(_ port: UInt16) -> Bool {
        guard let fd = socketAt(port) else { return false }
        defer { close(fd) }
        let greeting: [UInt8] = [5, 1, 0]
        guard greeting.withUnsafeBytes({ send(fd, $0.baseAddress, $0.count, 0) }) == 3 else {
            return false
        }
        var reply = [UInt8](repeating: 0, count: 2)
        let size = reply.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, MSG_WAITALL) }
        return size == 2 && reply == [5, 0]
    }

    static func main() {
#if !targetEnvironment(simulator)
        print("REFUSE_NON_SIMULATOR"); exit(20)
#else
        let ports: [UInt16] = [39879, 39880, 39882]
        guard ports.allSatisfy(closed),
              (invoke("xrayVersion")?["data"] as? [String: Any])?["version"] as? String == "26.11.9",
              running() == false else { print("PRECHECK_FAILED"); exit(21) }
        for (index, vision) in [false, true].enumerated() {
            let key = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
                .base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let profile = "vless://\(UUID().uuidString.lowercased())@127.0.0.1:39882?" +
                "encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk=\(key)&sid=abcd" +
                (vision ? "&flow=xtls-rprx-vision" : "")
            let port = ports[index]
            do {
                let candidate = try VLESSRealityShareLink.parse(profile)
                guard let conversion = invokeJSON(try candidate.conversionRequest()) else {
                    print("CONVERSION_UNAVAILABLE"); exit(22)
                }
                let config: Data
                do {
                    config = try XrayVLESSRuntimeConfig.prepare(
                        candidate: candidate, converterResponse: conversion, socksPort: Int(port))
                } catch {
                    if let r = try? JSONSerialization.jsonObject(with: conversion) as? [String: Any],
                       let data = r["data"] as? [String: Any],
                       let out = (data["outbounds"] as? [[String: Any]])?.first {
                        print("CONVERTER_KEYS_" + out.keys.sorted().joined(separator: ","))
                        if let s = out["settings"] as? [String: Any] { print("SETTINGS_KEYS_" + s.keys.sorted().joined(separator: ",")) }
                        if let s = out["streamSettings"] as? [String: Any] {
                            print("STREAM_KEYS_" + s.keys.sorted().joined(separator: ","))
                            if let r = s["realitySettings"] as? [String: Any] { print("REALITY_KEYS_" + r.keys.sorted().joined(separator: ",")) }
                        }
                    }
                    throw error
                }
                guard let json = String(data: config, encoding: .utf8),
                      invoke("testXray", config: json) != nil else {
                    print("PINNED_TEST_XRAY_REJECTED"); exit(23)
                }
                let started = invoke("runXray", config: json) != nil
                let live = started && running() == true
                let greeting = live && socksGreeting(port)
                let stopped = invoke("stopXray") != nil && running() == false && closed(port)
                guard started, live, greeting, stopped else {
                    print("LIFECYCLE_FAILED_START_\(started)_RUN_\(live)_SOCKS_\(greeting)_STOP_\(stopped)")
                    exit(24)
                }
                print("APL_XRAY_NATIVE_CONFIG_VISION_\(vision)_CONVERT_TEST_RUN_SOCKS_STOP_PASS")
            } catch {
                _ = invoke("stopXray")
                print("APL_XRAY_NATIVE_CONFIG_FAILED_CASE_\(index)_TYPE_\(type(of: error))")
                exit(25)
            }
        }
        print("APL_XRAY_NATIVE_CONFIG_2_CASES_PASS")
#endif
    }
}
