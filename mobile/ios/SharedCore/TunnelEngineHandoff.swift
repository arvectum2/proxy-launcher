import Foundation

/// A blocking tun2proxy run occupies its serial engine queue until it exits.
/// A fixed sleep after stop() does not prove that the queue is free. This
/// barrier only completes once all work submitted before it has finished.
///
/// Do not call from the same serial queue. On timeout, the caller must fail
/// the NetworkExtension tunnel instead of scheduling a replacement runner.
enum TunnelEngineDrainError: Error, Equatable {
    case timeout
}

enum TunnelEngineHandoff {
    private final class CompletionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var completed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !completed else { return false }
            completed = true
            return true
        }
    }

    static func stopAndDrain(
        engineQueue: DispatchQueue,
        timeout: TimeInterval = 5,
        stop: () -> Void
    ) async throws {
        // Stop synchronously before queuing the barrier: the previous runner
        // may be blocked on this queue, so dispatching stop here deadlocks.
        stop()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = CompletionGate()
            engineQueue.async {
                if gate.claim() {
                    continuation.resume(returning: ())
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, timeout)) {
                if gate.claim() {
                    continuation.resume(throwing: TunnelEngineDrainError.timeout)
                }
            }
        }
    }
}
