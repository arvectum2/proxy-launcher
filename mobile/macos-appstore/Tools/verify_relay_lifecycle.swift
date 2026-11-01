import Foundation

@main
struct RelayLifecycleSmoke {
    static func main() {
        let policy = RelayConnectionPolicy()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let past = { (sec: TimeInterval) in now.addingTimeInterval(-sec) }
        precondition(policy.maximumPairs == 90)
        precondition(policy.acceptsNewPair(existingPairs: 89))
        precondition(!policy.acceptsNewPair(existingPairs: 90))
        precondition(!policy.shouldClose(now: now, createdAt: past(15), lastActivityAt: past(15)))
        precondition(!policy.shouldClose(now: now, createdAt: past(74), lastActivityAt: past(74)))
        precondition(policy.shouldClose(now: now, createdAt: past(75), lastActivityAt: past(75)))
        precondition(policy.shouldClose(now: now, createdAt: past(600), lastActivityAt: past(75)))
        precondition(!policy.shouldClose(now: now, createdAt: past(600), lastActivityAt: past(10)))
        precondition(policy.shouldClose(now: now, createdAt: past(901), lastActivityAt: past(1)))
        print("PASS: 9 relay capacity, idle reaping, activity and maximum-age assertions")
    }
}
