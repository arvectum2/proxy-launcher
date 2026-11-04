#if DEBUG && !targetEnvironment(macCatalyst)
import Foundation
import Network
import Security

/// Test-only physical IPv6 TLS/HTTP evidence; no VPN, no profile changes.
/// Each request is bound to an explicit underlay via Network.framework.
@MainActor
enum IPv6PhysicalDiagnosticsQA {
    private static var connections: [NWConnection] = []

    static func start() {
        guard ProcessInfo.processInfo.arguments.contains("-aplIPv6PhysicalDiagnosticsQA")
        else { return }
        connections.forEach { $0.cancel() }
        connections.removeAll()
        let queue = DispatchQueue(label: "ru.arvectum.apl.ipv6.physical.qa")
        let hostname = "ipv6.google.com" // AAAA-only hostname
        // Three distinct physical HTTPS sessions: Wi-Fi → cellular → Wi-Fi,
        // independently validated by NWConnection currentPath and USB RVI
        // packet origins. No actual owner Wi-Fi radio switch is required.
        let sequence: [(String, NWInterface.InterfaceType)] = [
            ("wifi-first", .wifi),
            ("cellular", .cellular),
            ("wifi-return", .wifi)
        ]
        Task { @MainActor in
            for (index, (name, interface)) in sequence.enumerated() {
                if index > 0 {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                }
                let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, hostname)
            let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
            params.requiredInterfaceType = interface
            let connection = NWConnection(host: NWEndpoint.Host(hostname),
                                          port: .https, using: params)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let bound = connection.currentPath?.usesInterfaceType(interface) == true
                    TelemetryStore().append(TunnelEvent(type: "lab ipv6 tls ready",
                        detail: "\(name); bound=\(bound ? 1 : 0); ipv6=\(connection.currentPath?.supportsIPv6 == true ? 1 : 0)"))
                    connection.send(content: Data(
                        "GET / HTTP/1.1\r\nHost: \(hostname)\r\nConnection: close\r\n\r\n".utf8),
                        completion: .contentProcessed { err in
                            if let err {
                                TelemetryStore().append(TunnelEvent(type: "lab ipv6 send failed",
                                    detail: "\(name); \(err.localizedDescription.prefix(80))"))
                            }
                        })
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 512) {
                        data, _, _, error in
                        if let data, !data.isEmpty {
                            TelemetryStore().append(TunnelEvent(type: "lab ipv6 http data",
                                detail: "\(name); bytes=\(data.count)"))
                        } else {
                            TelemetryStore().append(TunnelEvent(type: "lab ipv6 http empty",
                                detail: "\(name); \(error?.localizedDescription.prefix(80) ?? "eof")"))
                        }
                    }
                case .failed(let error):
                    TelemetryStore().append(TunnelEvent(type: "lab ipv6 tls failed",
                        detail: "\(name); \(error.localizedDescription.prefix(80))"))
                case .cancelled:
                    break
                default:
                    break
                }
            }
                connection.start(queue: queue)
                connections.append(connection)
            }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }
}
#endif
