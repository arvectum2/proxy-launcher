import Foundation

struct FailoverTuning {
    var failureThreshold = 3
    var switchCooldown: TimeInterval = 20
    var recentlyFailedSuppression: TimeInterval = 60
    var healthInterval: TimeInterval = 6
    var backupScanInterval: TimeInterval = 30
}

struct FailoverPolicy {
    var tuning = FailoverTuning()

    func failureConfirmed(_ consecutiveFailures: Int) -> Bool {
        consecutiveFailures >= tuning.failureThreshold
    }

    func cooldownElapsed(now: Date, lastSwitch: Date?) -> Bool {
        guard let lastSwitch else { return true }
        return now.timeIntervalSince(lastSwitch) >= tuning.switchCooldown
    }

    func recentlyFailedStillSuppressed(now: Date, failedAt: Date?) -> Bool {
        guard let failedAt else { return false }
        return now.timeIntervalSince(failedAt) < tuning.recentlyFailedSuppression
    }

    func orderCandidates(profileIDs: [UUID], primaryID: UUID?, lastSuccessfulID: UUID?, recentlyFailedID: UUID?) -> [UUID] {
        var result: [UUID] = []
        for id in [primaryID, lastSuccessfulID].compactMap({ $0 }) + profileIDs {
            if profileIDs.contains(id), !result.contains(id) { result.append(id) }
        }
        if let recentlyFailedID, let index = result.firstIndex(of: recentlyFailedID) {
            result.remove(at: index)
            result.append(recentlyFailedID)
        }
        return result
    }

    func shouldRestorePrimary(
        policy: PrimaryRestorePolicy,
        currentID: UUID?,
        primaryID: UUID?,
        primaryAvailable: Bool,
        now: Date,
        lastSwitch: Date?
    ) -> Bool {
        policy == .returnToPrimary &&
        primaryAvailable &&
        currentID != nil &&
        primaryID != nil &&
        currentID != primaryID &&
        cooldownElapsed(now: now, lastSwitch: lastSwitch)
    }
}
