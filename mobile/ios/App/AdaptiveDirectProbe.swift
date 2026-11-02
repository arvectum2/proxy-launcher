import Foundation
import Network
import Security

/// Experimental, connection-only diagnostic. This is NOT a VPN bypass and
/// does not certify physical egress; the system can still enforce VPN scoping.
/// It never downloads a web page, cookies, credentials, or user data.
enum AdaptiveDirectProbe {
    enum Result: Equatable {
        case tlsReadyViaWiFi
        case tlsReadyViaCellular
        case unavailable
    }

    static func checkTLS(host: String, timeout: TimeInterval = 7) async -> Result {
        let name = host.lowercased()
        guard SiteDependencyDiscovery.isScannableHost(name),
              SiteDependencyDiscovery.eligibleForAutomaticBypass(name),
              timeout > 0, timeout <= 15 else { return .unavailable }
        if await attempt(name, interface: .wifi, timeout: timeout) { return .tlsReadyViaWiFi }
        if Task.isCancelled { return .unavailable }
        if await attempt(name, interface: .cellular, timeout: timeout) { return .tlsReadyViaCellular }
        return .unavailable
    }

    private static func attempt(_ host: String, interface: NWInterface.InterfaceType,
                                timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
            let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
            parameters.requiredInterfaceType = interface
            let connection = NWConnection(host: NWEndpoint.Host(host), port: .https, using: parameters)
            let queue = DispatchQueue(label: "ru.arvectum.apl.smart.directprobe")
            // Both completion paths execute on one serial queue.
            var completed = false
            func finish(_ result: Bool) {
                guard !completed else { return }
                completed = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // TLS handshake success alone is not a proof of a
                    // non-tunnel route; verify actual interface attribution.
                    finish(connection.currentPath?.usesInterfaceType(interface) == true)
                case .failed, .cancelled:
                    finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}
