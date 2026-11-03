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
    private var exactHostDirect = false
    private var directTTLSeconds: TimeInterval = AdaptiveRouteLearning.lifetime
    private var activeDirectHosts: Set<String> = []
    private var pathMonitors: [NWPathMonitor] = []
    private var pathSnapshots: [String: String] = [:]
    private var inflight: Set<String> = []
#if DEBUG
    private var labFlowEventBudget = 0
    private var labPhysicalFamilyBudget = 0
#endif


    func start(store: ProfileStore,
               exactHostDirect: Bool = AdaptiveRouteCapabilities.iosPacketTunnelExactHostDirect,
               labScopedDirect: Bool = false,
               qaDirectTTLSeconds: TimeInterval = AdaptiveRouteLearning.lifetime) {
        queue.sync {
            for monitor in pathMonitors { monitor.cancel() }
            pathMonitors.removeAll()
            pathSnapshots.removeAll()
            activeDirectHosts.removeAll()
            self.exactHostDirect = exactHostDirect
            self.directTTLSeconds = labScopedDirect && (4...10).contains(qaDirectTTLSeconds)
                ? qaDirectTTLSeconds : AdaptiveRouteLearning.lifetime
            self.store = store
            runtimeID = UUID().uuidString
            successfulHosts.removeAll()
            inflight.removeAll()
#if DEBUG
            labFlowEventBudget = 0
            labPhysicalFamilyBudget = 0
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
        startUnderlayGuard()
    }

    func stop() {
        tun2proxy_set_flow_event_callback(nil, nil)
        queue.sync {
            for monitor in pathMonitors { monitor.cancel() }
            pathMonitors.removeAll()
            pathSnapshots.removeAll()
            for host in activeDirectHosts {
                _ = host.withCString { tun2proxy_set_direct_exact_host($0, false) }
            }
            activeDirectHosts.removeAll()
            exactHostDirect = false
            enabled = false
            labScopedDirect = false
            inflight.removeAll()
            store = nil
            successfulHosts.removeAll()
        }
    }

    static let shared = SmartFlowEventCollector()

    /// Watch underlay and interface availability separately. A new Wi-Fi
    /// gateway or the handoff to cellular invalidates the learned evidence.
    /// Revoking is conservative: no stale grant survives the change.
    private func startUnderlayGuard() {
        queue.async { [weak self] in
            guard let self, self.enabled, self.exactHostDirect else { return }
            let watches: [(String, NWPathMonitor)] = [
                ("default", NWPathMonitor()),
                ("wifi", NWPathMonitor(requiredInterfaceType: .wifi)),
                ("cellular", NWPathMonitor(requiredInterfaceType: .cellular))
            ]
            for (name, monitor) in watches {
                monitor.pathUpdateHandler = { [weak self] path in
                    guard let self, self.enabled else { return }
                    let fingerprint = self.pathFingerprint(path)
                    if let previous = self.pathSnapshots[name], previous != fingerprint {
                        self.revokeAllDirect(reason: "network changed")
                    }
                    self.pathSnapshots[name] = fingerprint
                }
                self.pathMonitors.append(monitor)
                monitor.start(queue: self.queue)
            }
        }
    }

    private func pathFingerprint(_ path: NWPath) -> String {
        let interfaces = path.availableInterfaces.map {
            "\($0.name):\($0.type)"
        }.sorted().joined(separator: ",")
        let gateways = path.gateways.map { String(describing: $0) }
            .sorted().joined(separator: ",")
        return "\(path.status)|\(path.isExpensive)|\(path.isConstrained)|" +
            "\(path.usesInterfaceType(.wifi))|\(path.usesInterfaceType(.cellular))|" +
            "\(interfaces)|\(gateways)"
    }

    /// Must be called on the collector's serial queue. In-flight approval
    /// probes are invalidated by a fresh generation id and cannot re-arm.
    private func revokeAllDirect(reason: String) {
        guard enabled else { return }
        for host in activeDirectHosts {
            _ = host.withCString { tun2proxy_set_direct_exact_host($0, false) }
        }
        let hadDirect = !activeDirectHosts.isEmpty
        activeDirectHosts.removeAll()
        inflight.removeAll()
        successfulHosts.removeAll()
        runtimeID = UUID().uuidString
        if let store {
            var learning = store.adaptiveRouteLearning
            learning.prune(at: Date(), networkID: runtimeID)
            store.adaptiveRouteLearning = learning
        }
        if hadDirect {
            telemetry.append(TunnelEvent(type: "smart direct reverted",
                detail: reason))
        }
    }

#if DEBUG
    /// Deterministic revocation test without touching the owner's Wi-Fi.
    func forceNetworkChangeForQA() {
        queue.async { [weak self] in self?.revokeAllDirect(reason: "qa network change") }
    }
#endif

    private func accept(host: String, id: UInt64, event: Int32) {
        queue.async { [weak self] in
            guard let self, self.enabled else { return }
            let now = Date()
            self.successfulHosts = self.successfulHosts.filter {
                now.timeIntervalSince($0.value) < 60
            }
#if DEBUG
            // Only the two disposable browser-test hosts; bounded and no secrets.
            if self.labScopedDirect && self.labFlowEventBudget < 16 &&
                (host == "start.qa-example.test" || host == "www.apple.com") {
                self.labFlowEventBudget += 1
                let origin = host == "start.qa-example.test" ? "origin" : "target"
                let healthy = self.successfulHosts.contains { $0.key != host }
                self.telemetry.append(TunnelEvent(type: "lab browser flow observed",
                    detail: "\(origin); code=\(event); peerHealthy=\(healthy ? 1 : 0)"))
            }
#endif
            if event == 0 {
#if DEBUG
                if self.labScopedDirect && host == "www.apple.com.cn" {
                    self.telemetry.append(TunnelEvent(type: "lab neighbor via proxy",
                        detail: "Distinct exact virtual-DNS host CONNECT accepted by upstream"))
                }
                if self.labScopedDirect && host == "ipv6.l.google.com" {
                    self.telemetry.append(TunnelEvent(type: "lab ipv6 neighbor via proxy",
                        detail: "Distinct canonical IPv6 DNS host stays on upstream"))
                }
#endif
                self.successfulHosts[host] = now
                if self.successfulHosts.count > 32 {
                    if let oldest = self.successfulHosts.min(by: { $0.value < $1.value })?.key {
                        self.successfulHosts.removeValue(forKey: oldest)
                    }
                }
                return
            }
#if DEBUG
            if (event == 10 || event == 11), self.labScopedDirect {
                // Bound diagnostic journal: do not push older evidence out of
                // the compact on-device event ring with repeated TLS retries.
                if self.labPhysicalFamilyBudget < 3 {
                    self.labPhysicalFamilyBudget += 1
                    self.telemetry.append(TunnelEvent(type:
                        event == 10 ? "lab physical tcp ipv4" : "lab physical tcp ipv6",
                        detail: "Actual direct TCP socket address family"))
                }
                return
            }
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
#endif
            // A scoped TCP failure revokes authorization in BOTH build modes.
            if event == 5, self.exactHostDirect, let store = self.store {
                _ = host.withCString { tun2proxy_set_direct_exact_host($0, false) }
                self.activeDirectHosts.remove(host)
                var learning = store.adaptiveRouteLearning
                _ = learning.directFailure(host)
                store.adaptiveRouteLearning = learning
                self.telemetry.append(TunnelEvent(type: self.labScopedDirect ?
                    "lab direct reverted" : "smart direct reverted",
                    detail: "Direct TCP failed; returned to proxy"))
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
                if self.exactHostDirect {
                    self.launchDirectProbe(host: host, runtime: self.runtimeID, store: store)
                } else {
                    self.telemetry.append(TunnelEvent(type: "smart candidate",
                        detail: "Повторные ошибки подключения; рекомендация доступна в исключениях"))
                }
            }
        }
    }

    private func launchDirectProbe(host: String, runtime: String, store: ProfileStore) {
        guard inflight.count < 3, inflight.insert(host).inserted else { return }
        if labScopedDirect {
            telemetry.append(TunnelEvent(type: "lab scoped probe started",
                detail: "Two sequential TLS sessions will use physical interfaces"))
        }
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
                guard self.enabled, self.exactHostDirect, self.runtimeID == runtime else { return }
                var learning = store.adaptiveRouteLearning
                let ok = first && second
                if self.labScopedDirect {
                    self.telemetry.append(TunnelEvent(type: "lab scoped probe results",
                        detail: "first=\(first ? 1 : 0); second=\(second ? 1 : 0)"))
                }
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
                        self.activeDirectHosts.insert(host)
                        self.telemetry.append(TunnelEvent(type: self.labScopedDirect ?
                            "lab direct armed" : "smart direct armed",
                            detail: "Two independent physical TLS probes passed"))
                        self.queue.asyncAfter(deadline: .now() + self.directTTLSeconds) { [weak self] in
                            guard let self, self.enabled, self.runtimeID == runtime,
                                  self.activeDirectHosts.remove(host) != nil else { return }
                            _ = host.withCString { tun2proxy_set_direct_exact_host($0, false) }
                            if let store = self.store {
                                var learning = store.adaptiveRouteLearning
                                _ = learning.directFailure(host)
                                store.adaptiveRouteLearning = learning
                            }
                            self.telemetry.append(TunnelEvent(type: "smart direct expired",
                                detail: "Temporary exact-host route returned to proxy"))
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
}

/// Independent physical-interface TLS verification, not a probe through VPN.
/// Fail closed if Wi-Fi/cellular cannot be explicitly selected or TLS fails.
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
