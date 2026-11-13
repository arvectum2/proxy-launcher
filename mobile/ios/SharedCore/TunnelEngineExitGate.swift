import Foundation

/// Thread-safe ownership gate for a blocking tun2proxy runner. A native
/// exit while the VPN is live must stop the tunnel, including exit code zero.
final class TunnelEngineExitGate: @unchecked Sendable {
    private enum State { case idle, running, failed }
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var state: State = .idle

    @discardableResult
    func begin() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        state = .running
        return generation
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        state = .idle
    }

    func isRunning(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token == generation && state == .running
    }

    /// Exactly one unexpected exit owns the failure for this generation.
    func markUnexpectedExit(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard token == generation && state == .running else { return false }
        state = .failed
        return true
    }

    /// Recheck the generation when the cancellation reaches the main queue.
    func shouldCancelTunnel(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token == generation && state == .failed
    }
}
