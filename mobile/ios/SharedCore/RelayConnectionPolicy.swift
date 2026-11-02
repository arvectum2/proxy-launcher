import Foundation

/// Bounded TLS relay connections: stale HTTP keep-alive sessions cannot
/// accumulate indefinitely when an upstream peer half-closes TCP sockets.
struct RelayConnectionPolicy {
    let maximumPairs: Int
    let maximumIdleSeconds: TimeInterval
    let maximumAgeSeconds: TimeInterval

    init(maximumPairs: Int = 90,
         maximumIdleSeconds: TimeInterval = 75,
         maximumAgeSeconds: TimeInterval = 15 * 60) {
        self.maximumPairs = maximumPairs
        self.maximumIdleSeconds = maximumIdleSeconds
        self.maximumAgeSeconds = maximumAgeSeconds
    }

    func shouldClose(now: Date, createdAt: Date, lastActivityAt: Date) -> Bool {
        now.timeIntervalSince(lastActivityAt) >= maximumIdleSeconds ||
        now.timeIntervalSince(createdAt) >= maximumAgeSeconds
    }

    func acceptsNewPair(existingPairs: Int) -> Bool {
        existingPairs < maximumPairs
    }
}
