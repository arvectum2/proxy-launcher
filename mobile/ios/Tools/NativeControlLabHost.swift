// Shared by both mutually exclusive NativeLab variants, never production.
import Foundation
import NetworkExtension

@MainActor final class NativeControlLabHost {
    private let endpoint: NETunnelNativeControlEndpoint
    private let slot: OwnedNativeControlSlot
    private let session: TransportBackendCoordinator.Session
    private var ready = false, connected = false, drained = false, off = false, failed = false
    private(set) var staleRejected = false
    init(manager: NETunnelProviderManager, transport: TransportProtocol,
         options: [String: NSObject], externalQuiescenceConfirmed: Bool) throws {
        // The external supervised runner checks no live extension before launch.
        // It is not inferred from a disconnected OS status alone.
        let plan = try TransportBackendPlan.prepare(profileID: UUID(), revision: UUID(), protocol: transport,
                                                    scope: .syntheticLab, routes: .tunnelOnly, required: [.tcpIPv4])
        var coordinator = TransportBackendCoordinator()
        guard case .start(let origin) = try coordinator.begin(plan) else { throw TransportAdapterError.unreconciled }
        session = origin
        endpoint = try NETunnelNativeControlEndpoint(manager: manager, provider: plan.provider) { _ in options }
        slot = OwnedNativeControlSlot(endpoint: endpoint, initialNativeQuiescenceVerified: externalQuiescenceConfirmed)
        slot.onReceipt = { [weak self] receipt, origin in
            guard let self, origin == self.session else { return }
            switch receipt {
            case .nativeReady: self.ready = true
            case .osConnected: self.connected = true
            case .nativeDrained: self.drained = true
            case .osDisconnected: self.off = true
            case .failed, .unexpectedExit: self.failed = true
            }
        }
    }
    var report: [String: Bool] {
        ["nativeReady":ready, "nativeOSConnected":connected, "nativeStaleRejected":staleRejected,
         "nativeDrained":drained, "nativeOSOff":off, "nativeFailure":failed]
    }
    private func wait(_ predicate: () -> Bool, seconds: UInt64) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + seconds * 1_000_000_000
        while !failed && !Task.isCancelled && DispatchTime.now().uptimeNanoseconds < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return !failed && !Task.isCancelled && predicate()
    }
    func start() async throws {
        do {
            try slot.submit(.start(session))
            guard await wait({ready && connected},seconds:10) else { throw TransportAdapterError.unreconciled }
            // Correct provider, wrong epoch: must not be accepted by the bound engine.
            let stale = TransportNativeIdentity(epoch: UUID(), generation: session.token.generation,
                                                provider: session.plan.provider == .rustXray ? "rust-xray" : "standalone-awg")
            staleRejected = try await endpoint.rejectsStaleObservation(.init(identity:stale,action:.observe))
            guard staleRejected, !failed, endpoint.status == .connected else { throw TransportAdapterError.unreconciled }
        } catch { cancel(); throw error }
    }
    func finish() async -> Bool {
        guard ready, connected, staleRejected, !failed else { cancel(); return false }
        do {
            try slot.submit(.stop(session))
            guard await wait({drained && off},seconds:10), try slot.isQuiescent() else { throw TransportAdapterError.unreconciled }
            return true
        } catch { cancel(); return false }
    }
    private func cancel() {
        failed = true
        try? slot.submit(.cancelTunnel(session))
    }
}
