import Foundation
import tun2proxy

/// Receives only sanitized exact-DNS-host TCP CONNECT outcomes from the
/// source-pinned Rust engine. Never changes routes or sends data to a server.
final class SmartFlowEventCollector {
    private let queue = DispatchQueue(label: "ru.arvectum.apl.smart.flow-events")
    private let telemetry = TelemetryStore()
    private var store: ProfileStore?
    private var runtimeID = ""
    private var successfulHosts: [String: Date] = [:]
    private var enabled = false

    func start(store: ProfileStore) {
        queue.sync {
            self.store = store
            runtimeID = UUID().uuidString
            successfulHosts.removeAll()
            enabled = true
        }
        tun2proxy_set_flow_event_callback({ hostPointer, connectionID, event, _ in
            guard let hostPointer else { return }
            let host = String(cString: hostPointer)
            SmartFlowEventCollector.shared.accept(host: host, id: connectionID, event: event)
        }, nil)
    }

    func stop() {
        tun2proxy_set_flow_event_callback(nil, nil)
        queue.sync {
            enabled = false
            store = nil
            successfulHosts.removeAll()
        }
    }

    static let shared = SmartFlowEventCollector()

    private func accept(host: String, id: UInt64, event: Int32) {
        queue.async { [weak self] in
            guard let self, self.enabled else { return }
            let now = Date()
            self.successfulHosts = self.successfulHosts.filter {
                now.timeIntervalSince($0.value) < 60
            }
            if event == 0 {
                self.successfulHosts[host] = now
                if self.successfulHosts.count > 32 {
                    if let oldest = self.successfulHosts.min(by: { $0.value < $1.value })?.key {
                        self.successfulHosts.removeValue(forKey: oldest)
                    }
                }
                return
            }
            // Event 3 means generic handshake failure; event 4 is a GLOBAL
            // supplier network problem. Neither is evidence of site blocking.
            guard event == 1 || event == 2, let store = self.store else { return }
            let healthy = self.successfulHosts.contains { $0.key != host }
            guard healthy else { return }
            var learning = store.adaptiveRouteLearning
            let action = learning.proxyFailure(host: host, connectionID: String(id),
                type: event == 1 ? .proxyTimeout : .proxyRefused,
                proxyHealthy: true, networkID: self.runtimeID, at: now)
            store.adaptiveRouteLearning = learning
            if case .verifyDirect = action {
                // The iOS PacketTunnel cannot safely perform an independent
                // exact-host DIRECT probe; present a diagnostic to the app.
                self.telemetry.append(TunnelEvent(type: "smart candidate",
                    detail: "Повторные ошибки подключения; рекомендация доступна в исключениях"))
            }
        }
    }
}
