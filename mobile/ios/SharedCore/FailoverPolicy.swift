import Foundation

struct FailoverTuning {
    var failureThreshold = 2
    var switchCooldown: TimeInterval = 20
    var recentlyFailedSuppression: TimeInterval = 60
    var healthInterval: TimeInterval = 10
    var backupScanInterval: TimeInterval = 30
    // Limit paid proxy handshakes and startup latency for 200-profile lists.
    var maxConnectionCandidates = 6
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

    func orderCandidates(profileIDs: [UUID], primaryID: UUID?, lastSuccessfulID: UUID?, recentlyFailedID: UUID?, latencies: [UUID: Int] = [:]) -> [UUID] {
        var result: [UUID] = []
        // User priority and last successful route remain authoritative. Rank
        // only the remaining backups by fresh observed latency, with unknown
        // entries retaining stable order. Failed candidates always go last.
        let backups = profileIDs.enumerated().sorted { left, right in
            let lhs = latencies[left.element], rhs = latencies[right.element]
            if lhs != nil && rhs == nil { return true }
            if lhs == nil && rhs != nil { return false }
            if let lhs, let rhs, lhs != rhs { return lhs < rhs }
            return left.offset < right.offset
        }.map(\.element)
        for id in [primaryID, lastSuccessfulID].compactMap({ $0 }) + backups {
            if profileIDs.contains(id), !result.contains(id) { result.append(id) }
        }
        if let recentlyFailedID, let index = result.firstIndex(of: recentlyFailedID) {
            result.remove(at: index)
            result.append(recentlyFailedID)
        }
        return result
    }

    /// Starting or failing over must not probe every imported paid endpoint.
    /// The main ranking still honors the user primary, last-good and measured
    /// backup latency; only the first bounded set is tested this round.
    func connectionCandidates(profileIDs: [UUID], primaryID: UUID?, lastSuccessfulID: UUID?, recentlyFailedID: UUID?, latencies: [UUID: Int] = [:]) -> [UUID] {
        let ordered = orderCandidates(profileIDs: profileIDs, primaryID: primaryID,
                                      lastSuccessfulID: lastSuccessfulID,
                                      recentlyFailedID: recentlyFailedID,
                                      latencies: latencies)
        // A freshly failed endpoint must not be retried immediately merely
        // because the imported list has fewer than the six-candidate cap.
        // Direct manual selection and later recovery probes remain available.
        let eligible = ordered.filter { $0 != recentlyFailedID }
        return Array(eligible.prefix(max(1, tuning.maxConnectionCandidates)))
    }

    /// A failed primary must not be reprobed on every monitor tick.
    /// Cooldown after switching and the independent backup probe interval
    /// both apply, including to unsuccessful checks.
    func shouldProbePrimary(now: Date, lastAttempt: Date?, lastSwitch: Date?) -> Bool {
        guard cooldownElapsed(now: now, lastSwitch: lastSwitch) else { return false }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= tuning.backupScanInterval
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
