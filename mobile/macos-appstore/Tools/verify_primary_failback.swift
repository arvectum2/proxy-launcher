import Foundation

// Only for this standalone test; production PrimaryRestorePolicy is part of ProfileStore.
enum PrimaryRestorePolicy {
    case stayOnBackup
    case returnToPrimary
}

@main
struct FailbackPolicySmoke {
    static func main() {
        let a = UUID(), b = UUID(), c = UUID()
        let logic = FailoverPolicy()
        let t = Date(timeIntervalSince1970: 1_810_000_000)
        let ordered = logic.orderCandidates(
            profileIDs: [b, c, a], primaryID: a,
            lastSuccessfulID: b, recentlyFailedID: nil
        )
        precondition(ordered == [a, b, c], "Healthy primary must be first")
        let afterFailure = logic.orderCandidates(
            profileIDs: [b, c, a], primaryID: a,
            lastSuccessfulID: b, recentlyFailedID: a
        )
        precondition(afterFailure == [b, c, a], "Failed primary must be last")
        precondition(!logic.shouldRestorePrimary(
            policy: .returnToPrimary, currentID: b, primaryID: a,
            primaryAvailable: false, now: t.addingTimeInterval(120),
            lastSwitch: t
        ), "Unreachable primary must not be restored")
        precondition(!logic.shouldRestorePrimary(
            policy: .stayOnBackup, currentID: b, primaryID: a,
            primaryAvailable: true, now: t.addingTimeInterval(120),
            lastSwitch: t
        ), "User manual preference must be respected")
        precondition(!logic.shouldRestorePrimary(
            policy: .returnToPrimary, currentID: b, primaryID: a,
            primaryAvailable: true, now: t.addingTimeInterval(10),
            lastSwitch: t
        ), "Cooldown suppresses premature failback")
        precondition(logic.shouldRestorePrimary(
            policy: .returnToPrimary, currentID: b, primaryID: a,
            primaryAvailable: true, now: t.addingTimeInterval(21),
            lastSwitch: t
        ), "Recovered primary must be restored")
        precondition(!logic.shouldRestorePrimary(
            policy: .returnToPrimary, currentID: a, primaryID: a,
            primaryAvailable: true, now: t.addingTimeInterval(120),
            lastSwitch: t
        ), "Primary must not switch to itself")
        precondition(!logic.failureConfirmed(2) && logic.failureConfirmed(3),
                     "Require three confirmed failures")
        precondition(logic.recentlyFailedStillSuppressed(
            now: t.addingTimeInterval(59), failedAt: t
        ), "Suppression must avoid immediate retry")
        precondition(!logic.recentlyFailedStillSuppressed(
            now: t.addingTimeInterval(60), failedAt: t
        ), "Suppression must expire")
        print("PASS: 10 primary, backup, restoration, cooldown and suppression assertions")
    }
}
