import Foundation
import Network
import Security
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
    private var labScopedDirect = false
    private var inflight: Set<String> = []


    func start(store: ProfileStore, labScopedDirect: Bool = false) {
        queue.sync {
            self.store = store
            runtimeID = UUID().uuidString
            successfulHosts.removeAll()
            inflight.removeAll()
#if DEBUG
            self.labScopedDirect = labScopedDirect
            if labScopedDirect {
                telemetry.append(TunnelEvent(type: "lab scoped enabled", detail: "DEBUG only"))
            }
#else
            self.labScopedDirect = false
#endif
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
            labScopedDirect = false
            inflight.removeAll()
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
#if DEBUG
            if event == 6, self.labScopedDirect {
                self.telemetry.append(TunnelEvent(type: "lab scoped tcp connected",
                    detail: "Physical bound TCP socket accepted; TLS proof separate"))
                return
            }
            if event == 7, self.labScopedDirect {
                self.telemetry.append(TunnelEvent(type: "lab sameflow recovered",
                    detail: "Original TCP flow resumed after proxy timeout over physical egress"))
                return
            }
            if (event == 8 || event == 9), self.labScopedDirect {
                // Exactly one event per direction for each approved direct
                // TCP session. Never log its payload or private destination.
                self.telemetry.append(TunnelEvent(type:
                    event == 8 ? "lab direct client bytes" : "lab direct server bytes",
                    detail: "First transferred TCP payload chunk observed"))
                return
            }
            if event == 5, self.labScopedDirect, let store = self.store {
                _ = host.withCString { tun2proxy_set_direct_exact_host($0, false) }
                var learning = store.adaptiveRouteLearning
                _ = learning.directFailure(host)
                store.adaptiveRouteLearning = learning
                self.telemetry.append(TunnelEvent(type: "lab direct reverted",
                    detail: "Scoped flow unsuccessful; automatically returned to PROXY"))
                return
            }
#endif
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
#if DEBUG
                if self.labScopedDirect {
                    self.launchLabProbe(host: host, runtime: self.runtimeID, store: store)
                } else {
                    self.telemetry.append(TunnelEvent(type: "smart candidate",
                        detail: "Повторные ошибки подключения; рекомендация доступна в исключениях"))
                }
#else
                self.telemetry.append(TunnelEvent(type: "smart candidate",
                    detail: "Повторные ошибки подключения; рекомендация доступна в исключениях"))
#endif
            }
        }
    }

#if DEBUG
    private func launchLabProbe(host: String, runtime: String, store: ProfileStore) {
        guard inflight.count < 3, inflight.insert(host).inserted else { return }
        telemetry.append(TunnelEvent(type: "lab scoped probe started",
            detail: "Two sequential TLS sessions will use physical interfaces"))
        Task { [weak self] in
            // Use the real completion timestamps, never synthesize a time
            // before proxyFailure.started: AdaptiveRouteLearning.prune would
            // reject the evidence as a clock regression.
            let first = await TunnelScopedTLSProbe.check(host: host)
            let firstAt = Date()
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            let second = await TunnelScopedTLSProbe.check(host: host)
            let secondAt = Date()
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.inflight.remove(host)
                guard self.enabled, self.labScopedDirect, self.runtimeID == runtime else { return }
                var learning = store.adaptiveRouteLearning
                let ok = first && second
                self.telemetry.append(TunnelEvent(type: "lab scoped probe results",
                    detail: "first=\(first ? 1 : 0); second=\(second ? 1 : 0)"))
                let one = learning.comparison(host: host, proxyFailed: true,
                    directSucceeded: ok, independentlyDirect: ok,
                    exactHostTransport: true, networkID: runtime,
                    at: firstAt)
                let two = learning.comparison(host: host, proxyFailed: true,
                    directSucceeded: ok, independentlyDirect: ok,
                    exactHostTransport: true, networkID: runtime, at: secondAt)
                if case .temporaryDirect = two, ok {
                    let applied = host.withCString { tun2proxy_set_direct_exact_host($0, true) }
                    if applied == 0 {
                        self.telemetry.append(TunnelEvent(type: "lab direct armed",
                            detail: "Two physical TLS probes passed; exact-host TCP test enabled"))
                        self.queue.asyncAfter(deadline: .now() + AdaptiveRouteLearning.lifetime) { [weak self] in
                            guard let self, self.runtimeID == runtime else { return }
                            _ = host.withCString { tun2proxy_set_direct_exact_host($0, false) }
                        }
                    } else {
                        _ = learning.directFailure(host)
                    }
                }
                store.adaptiveRouteLearning = learning
                _ = one
            }
        }
    }
#endif
}

#if DEBUG
/// Only a laboratory connection check, not proof of Safari egress, and
/// never a release feature without Apple DTS confirmation.
private enum TunnelScopedTLSProbe {
    static func check(host: String) async -> Bool {
        if await attempt(host: host, interface: .wifi) { return true }
        return await attempt(host: host, interface: .cellular)
    }
    private static func attempt(host: String, interface: NWInterface.InterfaceType) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
            let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
            params.requiredInterfaceType = interface
            let connection = NWConnection(host: NWEndpoint.Host(host), port: .https, using: params)
            let queue = DispatchQueue(label: "ru.arvectum.apl.lab.directProbe")
            var done = false
            func finish(_ success: Bool) {
                guard !done else { return }
                done = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: success)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(connection.currentPath?.usesInterfaceType(interface) == true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) { finish(false) }
        }
    }
}
#endif
