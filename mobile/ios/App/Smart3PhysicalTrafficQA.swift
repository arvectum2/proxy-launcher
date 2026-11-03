#if DEBUG
import Foundation
import Network

/// Reproducible 20s hardware QA. Produces three ordinary app TCP flows;
/// nothing is persisted and no paid proxy/user session is contacted.
@MainActor enum Smart3PhysicalTrafficQA {
    private static var connections: [NWConnection] = []

    static func begin() {
        guard ProcessInfo.processInfo.arguments.contains("-aplEphemeralTunnelQA"),
              ProcessInfo.processInfo.arguments.contains("-aplSmart3LocalProxyQA") else { return }
        connections.forEach { $0.cancel() }
        connections.removeAll()
        let queue = DispatchQueue(label: "ru.arvectum.apl.smart3.qa-traffic")
        let labDirect = ProcessInfo.processInfo.arguments.contains("-aplSmart3ScopedDirectLabQA")
        let hosts = labDirect ? ["www.cloudflare.com", "www.apple.com", "www.apple.com"]
                              : ["probe.qa-example.test", "auth.qa-example.test", "auth.qa-example.test"]
        for host in hosts {
            // In scoped lab, the first two target connections perform a
            // genuine TLS handshake WHILE the upstream proxy is stalled.
            // Their original TCP streams must recover without a page reload.
            let connection = NWConnection(host: NWEndpoint.Host(host), port: .https,
                                          using: labDirect ? .tls : .tcp)
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    if labDirect && host == "www.apple.com" {
                        TelemetryStore().append(TunnelEvent(type: "lab sameflow tls ready",
                            detail: "Original stalled TLS client became ready without reconnect"))
                    }
                    connection.send(content: Data("GET / HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n".utf8),
                                    completion: .contentProcessed { _ in })
                    if labDirect && host == "www.apple.com" {
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) {
                            data, _, _, _ in
                            if let data, !data.isEmpty {
                                TelemetryStore().append(TunnelEvent(type: "lab sameflow tls data",
                                    detail: "Original stalled TLS flow received HTTP response bytes"))
                            }
                        }
                    }
                } else if case .failed = state {
                    if labDirect && host == "www.apple.com" {
                        TelemetryStore().append(TunnelEvent(type: "lab sameflow tls failed",
                            detail: "Original stalled TLS transport failed before application response"))
                    }
                }
            }
            connection.start(queue: queue)
            connections.append(connection)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds:
                labDirect ? 18_000_000_000 : 16_000_000_000)
            if labDirect {
                // A fresh fourth connection after the two proxy timeouts and
                // independent TLS probes tests actual per-flow routing.
                let host = "www.apple.com"
                let direct = NWConnection(host: NWEndpoint.Host(host), port: .https, using: .tls)
                direct.stateUpdateHandler = { state in
                    if case .ready = state {
                        TelemetryStore().append(TunnelEvent(type: "lab scoped tls ready",
                            detail: "Fourth TLS session succeeded with mock proxy denying target"))
                        print("APL_SCOPED_QA_TLS_READY")
                        direct.send(content: Data("GET / HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n".utf8),
                                    completion: .contentProcessed { _ in })
                        direct.receive(minimumIncompleteLength: 1, maximumLength: 256) {
                            data, _, _, _ in
                            if let data, !data.isEmpty {
                                TelemetryStore().append(TunnelEvent(type: "lab scoped tls data",
                                    detail: "Direct test TLS replied with bytes"))
                            }
                            print("APL_SCOPED_QA_RESPONSE_BYTES_\(data?.count ?? 0)")
                        }
                    } else if case .failed = state {
                        TelemetryStore().append(TunnelEvent(type: "lab scoped tls failed",
                            detail: "Fourth TLS session was unable to connect"))
                    }
                }
                TelemetryStore().append(TunnelEvent(type: "lab scoped tls attempt",
                    detail: "Fourth independent connection after direct policy armed"))
                direct.start(queue: queue)
                connections.append(direct)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }
}
#endif
