import Foundation

/// Lab-only commands. Driver submits nonblocking commands and delivers
/// independently verified native and OS receipts on MainActor.
@MainActor protocol TransportBackendDriver: AnyObject {
    func submit(_ command: TransportBackendCoordinator.Command) throws
    /// Fresh verification of BOTH owned provider slots, including no
    /// queued/in-flight starts and no live native runner.
    func allOwnedProvidersQuiescent() throws -> Bool
}

@MainActor final class TransportBackendLease {
    static let shared = TransportBackendLease()
    private var owner: UUID?
    func acquire(_ id: UUID) -> Bool {
        guard owner == nil || owner == id else { return false }
        owner = id
        return true
    }
    func release(_ id: UUID) {
        if owner == id { owner = nil }
    }
}

enum TransportAdapterError: Error, Equatable {
    case busy, unreconciled, invalidTimeout
}

enum TransportBackendReceipt: Equatable {
    case nativeReady, osConnected, nativeDrained, osDisconnected
    case unexpectedExit, failed
}

/// Inactive serialized lab adapter, not an actual NE driver or kill switch.
/// The real driver must bind receipts to the originating manager/session,
/// never manufacture a token from the current global VPN status.
@MainActor final class TransportBackendAdapter {
    typealias Model = TransportBackendCoordinator
    private let driver: TransportBackendDriver
    private let lease: TransportBackendLease
    private let owner = UUID()
    private let timeoutNS: UInt64
    private(set) var model = Model()
    private var nativeReady = false
    private var osConnected = false
    private var timer: Task<Void, Never>?
    private var deadline: UInt64?
    private var timerID: UUID?
    private var executing = false
    private var draining = false
    private var inspecting = false
    private var queued: [(Model.Session, TransportBackendReceipt)] = []

    init(driver: TransportBackendDriver, lease: TransportBackendLease? = nil,
         timeout: TimeInterval = 10) throws {
        guard timeout.isFinite, timeout >= 0.01, timeout <= 120 else {
            throw TransportAdapterError.invalidTimeout
        }
        self.driver = driver
        self.lease = lease ?? .shared
        self.timeoutNS = UInt64(timeout * 1_000_000_000)
    }

    func begin(_ plan: TransportBackendPlan) throws {
        guard !executing, !inspecting, !draining, model.phase == .idle else { throw TransportAdapterError.busy }
        guard lease.acquire(owner) else { throw TransportAdapterError.busy }
        do {
            guard try inspectQuiescence() else {
                throw TransportAdapterError.unreconciled
            }
            let command = try model.begin(plan)
            execute(command)
        } catch {
            lease.release(owner)
            drainEvents()
            throw error
        }
    }

    func switchTo(_ plan: TransportBackendPlan) throws {
        guard !executing, !inspecting, !draining, let active = model.active else { throw TransportAdapterError.busy }
        execute(try model.requestSwitch(to: plan, token: active.token))
    }

    func stop() throws {
        guard !executing, !inspecting, !draining, let active = model.active else { throw TransportAdapterError.busy }
        if let command = try model.requestStop(active.token) { execute(command) }
    }

    /// Failure retains ownership even if cancel throws. No automatic recovery.
    func reconcileFailure() throws {
        guard !executing, !inspecting, !draining, model.phase == .failedClosed else { throw TransportAdapterError.busy }
        guard try inspectQuiescence() else { throw TransportAdapterError.unreconciled }
        guard let old = model.active, !queued.contains(where: { origin,event in
            origin.token == old.token && (event == .nativeReady || event == .osConnected)
        }) else {
            drainEvents()
            throw TransportAdapterError.unreconciled
        }
        disarm()
        model = Model()
        nativeReady = false
        osConnected = false
        lease.release(owner)
        drainEvents()
    }

    func receive(_ receipt: TransportBackendReceipt, from origin: Model.Session) {
        queued.append((origin, receipt))
        drainEvents()
    }

    private func drainEvents() {
        guard !executing, !inspecting, !draining else { return }
        draining = true
        defer { draining = false }
        while !queued.isEmpty {
            let (origin, event) = queued.removeFirst()
            handle(event, from: origin)
        }
    }

    private func inspectQuiescence() throws -> Bool {
        inspecting = true
        defer { inspecting = false }
        return try driver.allOwnedProvidersQuiescent()
    }

    private func handle(_ receipt: TransportBackendReceipt, from origin: Model.Session) {
        guard let active = model.active, active.token == origin.token,
              model.phase != .failedClosed else { return }
        guard active == origin else { fail(active); return }
        if let deadline, DispatchTime.now().uptimeNanoseconds >= deadline {
            fail(active); return
        }
        do {
            switch receipt {
            case .failed, .unexpectedExit: fail(active)
            case .nativeReady, .osConnected:
                if model.phase == .stopping {
                    // Readiness after its corresponding stop receipt
                    // contradicts quiescence.
                    if (receipt == .nativeReady && model.nativeDrained) ||
                       (receipt == .osConnected && model.osDisconnected) {
                        fail(active)
                    }
                    return
                }
                guard model.phase == .starting else { return }
                if receipt == .nativeReady { nativeReady = true }
                else { osConnected = true }
                if nativeReady && osConnected {
                    if let c = try model.ready(active.token, provider: origin.plan.provider) {
                        execute(c)
                    } else { disarm() }
                }
            case .nativeDrained, .osDisconnected:
                guard model.phase == .stopping else { fail(active); return }
                // Before the second gate advances the model, verify both
                // slots stopped, including outstanding starts.
                let last = receipt == .nativeDrained ? model.osDisconnected : model.nativeDrained
                if last {
                    guard try inspectQuiescence() else { fail(active); return }
                    let contradicts = queued.contains { origin, event in
                        origin.token == active.token &&
                        (origin != active || event == .nativeReady || event == .osConnected ||
                         event == .unexpectedExit || event == .failed)
                    }
                    guard !contradicts else { fail(active); return }
                }
                let command = try receipt == .nativeDrained
                    ? model.acknowledgeNativeDrain(active.token)
                    : model.acknowledgeOSDisconnected(active.token)
                if let command { execute(command) }
                else if model.phase == .idle { disarm(); lease.release(owner) }
            }
        } catch { fail(active) }
    }

    private func execute(_ command: Model.Command) {
        let active: Model.Session
        switch command {
        case .start(let s):
            active = s
            nativeReady = false
            osConnected = false
            arm(s)
        case .stop(let s):
            active = s
            arm(s)
        case .cancelTunnel(let s):
            active = s
            disarm()
        }
        executing = true
        var failure = false
        do { try driver.submit(command) }
        catch { failure = true }
        executing = false
        // Submit failure takes precedence over synchronous success receipts.
        if failure { fail(active) }
        drainEvents()
    }

    private func fail(_ session: Model.Session) {
        guard let command = try? model.failClosed(session.token) else { return }
        execute(command)
    }

    private func arm(_ session: Model.Session) {
        disarm()
        let id = UUID()
        timerID = id
        let expiry = DispatchTime.now().uptimeNanoseconds + timeoutNS
        deadline = expiry
        timer = Task { @MainActor [weak self] in
            let now = DispatchTime.now().uptimeNanoseconds
            do { if now < expiry { try await Task.sleep(nanoseconds: expiry - now) } }
            catch { return }
            guard let self, self.timerID == id else { return }
            self.fail(session)
        }
    }

    private func disarm() {
        timer?.cancel()
        timer = nil
        timerID = nil
        deadline = nil
    }
}
