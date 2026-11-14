import Foundation

@MainActor protocol NativeControlEndpoint: AnyObject {
    var provider: TransportProvider { get }
    var status: NativeControlOSStatus { get }
    func start(_ session: TransportBackendCoordinator.Session, identity: TransportNativeIdentity) throws
    func exchange(_ request: TransportNativeRequest) async throws -> TransportNativeResponse
    func stop() throws
}

enum NativeControlOSStatus { case off, starting, connected, stopping, unknown }

/// Requires independent initial quiescence evidence. OS-disconnected alone
/// is insufficient. Lost drain receipts poison the slot; no fallback.
@MainActor final class OwnedNativeControlSlot: OwnedTransportSlot {
    typealias Model = TransportBackendCoordinator
    private let endpoint: NativeControlEndpoint
    private var active: Model.Session?
    private var knownDrained: Bool
    private var worker: Task<Void, Never>?
    private var workID: UUID?
    var onReceipt: ((TransportBackendReceipt, Model.Session) -> Void)?
    var provider: TransportProvider { endpoint.provider }

    init(endpoint: NativeControlEndpoint, initialNativeQuiescenceVerified: Bool) {
        self.endpoint = endpoint
        knownDrained = initialNativeQuiescenceVerified
    }
    func isQuiescent() throws -> Bool { knownDrained && active == nil && endpoint.status == .off && workID == nil }
    private func identity(_ session: Model.Session) -> TransportNativeIdentity {
        .init(epoch: session.token.epoch, generation: session.token.generation,
              provider: provider == .rustXray ? "rust-xray" : "standalone-awg")
    }
    func submit(_ command: Model.Command) throws {
        switch command {
        case .start(let session):
            guard try isQuiescent(), session.plan.provider == provider else { throw TransportAdapterError.unreconciled }
            active = session; knownDrained = false
            try endpoint.start(session, identity: identity(session))
            launch(session, stopping: false)
        case .stop(let session):
            guard active == session else { throw OwnedTransportDispatchError.foreignSession }
            launch(session, stopping: true)
        case .cancelTunnel(let session):
            guard active == session else { throw OwnedTransportDispatchError.foreignSession }
            invalidate(); knownDrained = false
            try endpoint.stop()
        }
    }
    private func invalidate() {
        workID = nil; worker?.cancel(); worker = nil
    }
    private func launch(_ session: Model.Session, stopping: Bool) {
        invalidate()
        let id = UUID(); workID = id
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.run(session, id: id, stopping: stopping)
        }
    }
    private func stillOwns(_ session: Model.Session, _ id: UUID) -> Bool {
        active == session && workID == id && !Task.isCancelled
    }
    private func run(_ session: Model.Session, id: UUID, stopping: Bool) async {
        do {
            if stopping {
                guard endpoint.status == .connected else { throw TransportAdapterError.unreconciled }
                let request = TransportNativeRequest(identity: identity(session), action: .drain)
                let response = try await endpoint.exchange(request)
                guard stillOwns(session,id) else { return }
                guard response.matches(request), response.state == .drained else { throw TransportAdapterError.unreconciled }
                onReceipt?(.nativeDrained, session)
                guard stillOwns(session,id) else { return }
                try endpoint.stop()
                while stillOwns(session,id) {
                    if endpoint.status == .off {
                        knownDrained = true; active = nil; invalidate()
                        onReceipt?(.osDisconnected, session); return
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                return
            }
            var announced = false
            while stillOwns(session,id) {
                switch endpoint.status {
                case .connected:
                    let request = TransportNativeRequest(identity: identity(session), action: .observe)
                    let response = try await endpoint.exchange(request)
                    guard stillOwns(session,id) else { return }
                    guard response.matches(request), endpoint.status == .connected else { throw TransportAdapterError.unreconciled }
                    if response.state == .ready {
                        if !announced {
                            announced = true; onReceipt?(.nativeReady,session)
                            guard stillOwns(session,id) else { return }
                            onReceipt?(.osConnected,session)
                        }
                    } else if response.state != .starting || announced { throw TransportAdapterError.unreconciled }
                case .starting:
                    if announced { throw TransportAdapterError.unreconciled }
                default: throw TransportAdapterError.unreconciled
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        } catch {
            guard stillOwns(session,id) else { return }
            invalidate(); knownDrained = false
            onReceipt?(.failed,session)
        }
    }
}
