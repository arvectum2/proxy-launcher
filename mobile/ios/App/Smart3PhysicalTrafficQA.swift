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
        for host in ["probe.qa-example.test", "auth.qa-example.test", "auth.qa-example.test"] {
            let connection = NWConnection(host: NWEndpoint.Host(host), port: .https, using: .tcp)
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.send(content: Data("GET / HTTP/1.1\r\nHost: \(host)\r\n\r\n".utf8),
                                    completion: .contentProcessed { _ in })
                }
            }
            connection.start(queue: queue)
            connections.append(connection)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 16_000_000_000)
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }
}
#endif
