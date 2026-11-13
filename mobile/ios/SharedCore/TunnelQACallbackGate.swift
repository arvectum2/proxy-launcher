import Foundation

/// Delayed Debug-only physical QA callbacks may never act on a newer VPN session.
final class TunnelQACallbackGate {
    // Recursive: supports synchronous provider stop notification while a QA
    // callback executes. Serializes stop/restart against the actual callback.
    private let lock = NSRecursiveLock()
    private var generation: UInt64 = 0
    private var active = false

    @discardableResult
    func begin() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        active = true
        return generation
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        active = false
    }

    func isCurrent(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return active && token == generation
    }

    /// Runs callback under gate's lock; action may call invalidate reentrantly.
    @discardableResult
    func performIfCurrent(_ token: UInt64, action: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard active && token == generation else { return false }
        action()
        return true
    }
}
