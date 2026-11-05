#if DEBUG
import Foundation
import Network

/// Separate QA app only. This intentionally does NOT observe or mutate the
/// owner's installed APL, App Group, VPN, PacketTunnel or Keychain.
/// Positive receipt proves physical LAN transport, NOT Smart4 tunnel egress.
enum Smart4TransportPhysicalQA {
    private static let framePrefix = "APL4/1 "
    private static let acknowledgement = Data("APL4/1 OK\n".utf8)
    private static let connectRequest = Data((
        "CONNECT apl-smart4-proxy.invalid:443 HTTP/1.1\r\n" +
        "Host: apl-smart4-proxy.invalid:443\r\n\r\n").utf8)
    private static let established = Data("HTTP/1.1 200\r\n\r\n".utf8)

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private static func privateIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let ints = parts.compactMap { Int($0) }
        guard ints.count == 4, ints.allSatisfy({ 0...255 ~= $0 }) else { return false }
        let a = ints[0], b = ints[1]
        return a == 10 || (a == 172 && 16...31 ~= b) || (a == 192 && b == 168)
    }

    private static func nonce(_ input: String?) -> String? {
        guard let input, input.count == 32,
              input.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            return nil
        }
        return input
    }

    @MainActor static func run(arguments args: [String]) async -> String {
        guard args.contains("-aplSmart4PhysicalTransportQA"),
              let address = value(after: "-aplSmart4PrivateIPv4", in: args),
              privateIPv4(address),
              let directValue = value(after: "-aplSmart4DirectPort", in: args),
              let proxyValue = value(after: "-aplSmart4ProxyPort", in: args),
              let directPort = UInt16(directValue), directPort > 0,
              let proxyPort = UInt16(proxyValue), proxyPort > 0,
              directPort != proxyPort,
              let directToken = nonce(value(after: "-aplSmart4DirectToken", in: args)),
              let proxyToken = nonce(value(after: "-aplSmart4ProxyToken", in: args)),
              directToken != proxyToken else { return "FAIL: private QA arguments" }
        do {
            // Compile the actual SharedCore production policy into this QA
            // bundle: different DNS hosts deliberately share a lab IPv4.
            let policy = try SmartFlowRoutingPolicy(
                manual: ["direct.qa.example.com"], graph: SmartExclusionGraph())
            let direct = policy.explain(host: "direct.qa.example.com", resolvedIP: address)
            let proxy = policy.explain(host: "proxy.qa.example.com", resolvedIP: address)
            guard direct == SmartRouteEvaluation(disposition: .direct,
                                                 reason: .manualExclusion),
                  proxy == SmartRouteEvaluation(disposition: .proxy,
                                                reason: .noMatchingPermission) else {
                return "FAIL: Smart4 shared-IP policy"
            }
        } catch { return "FAIL: Smart4 policy evaluation" }
        let directOK = await send(to: address, port: directPort,
                                  token: directToken, usingSyntheticRelay: false)
        let proxyOK = await send(to: address, port: proxyPort,
                                 token: proxyToken, usingSyntheticRelay: true)
        return "Smart4 model PASS; WiFi direct \(directOK ? "PASS" : "FAIL"); " +
               "synthetic proxy \(proxyOK ? "PASS" : "FAIL"); " +
               "PacketTunnel NOT VERIFIED"
    }
}
extension Smart4TransportPhysicalQA {
    private static func send(to host: String, port: UInt16, token: String,
                             usingSyntheticRelay: Bool) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let params = NWParameters.tcp
            // Both synthetic endpoints travel on physical Wi-Fi. The PROXY
            // path's sole distinction is its fixed local CONNECT relay;
            // neither is the real app's captured PacketTunnel flow.
            params.requiredInterfaceType = .wifi
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!, using: params)
            let queue = DispatchQueue(label: "ru.arvectum.smart4.lab-device")
            var completed = false
            func finish(_ success: Bool) {
                guard !completed else { return }
                completed = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: success)
            }
            func sendFrame() {
                let frame = Data((framePrefix + token + "\n").utf8)
                connection.send(content: frame, completion: .contentProcessed { error in
                    guard error == nil else { finish(false); return }
                    connection.receive(minimumIncompleteLength: acknowledgement.count,
                                       maximumLength: acknowledgement.count) {
                        data, _, _, _ in finish(data == acknowledgement)
                    }
                })
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    if usingSyntheticRelay {
                        connection.send(content: connectRequest,
                                        completion: .contentProcessed { error in
                            guard error == nil else { finish(false); return }
                            connection.receive(minimumIncompleteLength: established.count,
                                               maximumLength: established.count) {
                                data, _, _, _ in
                                guard data == established else { finish(false); return }
                                sendFrame()
                            }
                        })
                    } else { sendFrame() }
                case .failed: finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 9) { finish(false) }
        }
    }
}
#endif
