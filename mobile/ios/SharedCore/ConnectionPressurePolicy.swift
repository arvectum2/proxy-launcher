import Foundation

/// Limits socket accumulation inside Packet Tunnel without affecting other VPNs.
struct ConnectionPressurePolicy {
    struct Sample {
        let upstreamSockets: Int
        let closeWaitSockets: Int
    }

    private(set) var consecutivePressureSamples = 0
    private(set) var lastRecoveryAt: Date?
    let softSocketLimit: Int
    let softCloseWaitLimit: Int
    let hardSocketLimit: Int
    let hardCloseWaitLimit: Int
    let requiredConsecutiveSamples: Int
    let minimumRecoveryInterval: TimeInterval

    init(softSocketLimit: Int = 90,
         softCloseWaitLimit: Int = 25,
         hardSocketLimit: Int = 150,
         hardCloseWaitLimit: Int = 55,
         requiredConsecutiveSamples: Int = 2,
         minimumRecoveryInterval: TimeInterval = 2 * 60) {
        self.softSocketLimit = softSocketLimit
        self.softCloseWaitLimit = softCloseWaitLimit
        self.hardSocketLimit = hardSocketLimit
        self.hardCloseWaitLimit = hardCloseWaitLimit
        self.requiredConsecutiveSamples = requiredConsecutiveSamples
        self.minimumRecoveryInterval = minimumRecoveryInterval
    }

    /// Recover proactively before DNS requests stall as TCP sockets accumulate.
    /// Two consecutive 10-second samples debounce transient traffic bursts.
    /// Hard limits bypass the debounce, but not the minimum recovery interval.
    /// Recover only the embedded tun2proxy engine after sustained pressure.
    mutating func shouldRecover(sample: Sample, at now: Date, tunnelIsSwitching: Bool) -> Bool {
        guard !tunnelIsSwitching else {
            consecutivePressureSamples = 0
            return false
        }
        let soft = sample.upstreamSockets >= softSocketLimit ||
            sample.closeWaitSockets >= softCloseWaitLimit
        let hard = sample.upstreamSockets >= hardSocketLimit ||
            sample.closeWaitSockets >= hardCloseWaitLimit
        consecutivePressureSamples = soft ? consecutivePressureSamples + 1 : 0
        guard hard || consecutivePressureSamples >= requiredConsecutiveSamples else {
            return false
        }
        if let lastRecoveryAt {
            let elapsed = now.timeIntervalSince(lastRecoveryAt)
            // Retain cooldown through small NTP corrections. A large backwards
            // system-clock jump must not disable recovery for hours, however.
            if elapsed >= -minimumRecoveryInterval && elapsed < minimumRecoveryInterval {
                return false
            }
        }
        lastRecoveryAt = now
        consecutivePressureSamples = 0
        return true
    }
}

/// Reconnect only a recently crashed tunnel, never a deliberate manual stop.
/// Cap the number of automatic attempts so a broken proxy cannot create a loop.
struct TunnelAutoReconnectPolicy {
    private(set) var attempts: [Date] = []

    mutating func mayRetry(now: Date, failureAt: Date?, explicitDisconnect: Bool) -> Bool {
        guard !explicitDisconnect, let failureAt else { return false }
        let age = now.timeIntervalSince(failureAt)
        guard age >= 0, age <= 45 else { return false }
        attempts.removeAll {
            let elapsed = now.timeIntervalSince($0)
            // Drop attempts outside the bounded window in either direction:
            // a large backwards clock correction must not exhaust retry budget.
            return elapsed > 10 * 60 || elapsed < -(10 * 60)
        }
        guard attempts.count < 3 else { return false }
        attempts.append(now)
        return true
    }
}
