import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ConnectionPressurePolicyTests: XCTestCase {
    func testHealthyTunnelNeverRecycles() {
        var policy = ConnectionPressurePolicy()
        for tick in 0..<30 {
            XCTAssertFalse(policy.shouldRecover(
                sample: .init(upstreamSockets: 28, closeWaitSockets: 3),
                at: Date(timeIntervalSince1970: Double(tick * 30)),
                tunnelIsSwitching: false
            ))
        }
    }
    func testSustainedLeakRecyclesThenRespectsCooldown() {
        var policy = ConnectionPressurePolicy()
        let sample = ConnectionPressurePolicy.Sample(upstreamSockets: 105, closeWaitSockets: 40)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(policy.shouldRecover(sample: sample, at: start, tunnelIsSwitching: false))
        XCTAssertTrue(policy.shouldRecover(sample: sample, at: start.addingTimeInterval(10), tunnelIsSwitching: false))
        XCTAssertFalse(policy.shouldRecover(sample: sample, at: start.addingTimeInterval(20), tunnelIsSwitching: false))
        XCTAssertTrue(policy.shouldRecover(sample: sample, at: start.addingTimeInterval(151), tunnelIsSwitching: false))
    }
    func testHardLimitTriggersImmediately() {
        var policy = ConnectionPressurePolicy()
        XCTAssertTrue(policy.shouldRecover(
            sample: .init(upstreamSockets: 160, closeWaitSockets: 0),
            at: Date(), tunnelIsSwitching: false
        ))
    }
    func testObserved56CloseWaitRecoversBeforeDNSStarvation() {
        var policy = ConnectionPressurePolicy()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Actual 2026-11-01 symptom: 56 CLOSE_WAIT / 78 upstream.
        XCTAssertTrue(policy.shouldRecover(
            sample: .init(upstreamSockets: 78, closeWaitSockets: 56),
            at: now, tunnelIsSwitching: false
        ))
        // A second sample must not cause an immediate recovery loop.
        XCTAssertFalse(policy.shouldRecover(
            sample: .init(upstreamSockets: 78, closeWaitSockets: 56),
            at: now.addingTimeInterval(10), tunnelIsSwitching: false
        ))
        XCTAssertTrue(policy.shouldRecover(
            sample: .init(upstreamSockets: 78, closeWaitSockets: 56),
            at: now.addingTimeInterval(121), tunnelIsSwitching: false
        ))
    }

    func testLowTrafficBurstDoesNotTriggerRecovery() {
        var policy = ConnectionPressurePolicy()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(policy.shouldRecover(
            sample: .init(upstreamSockets: 78, closeWaitSockets: 25),
            at: now, tunnelIsSwitching: false
        ))
        XCTAssertFalse(policy.shouldRecover(
            sample: .init(upstreamSockets: 42, closeWaitSockets: 6),
            at: now.addingTimeInterval(10), tunnelIsSwitching: false
        ))
        XCTAssertFalse(policy.shouldRecover(
            sample: .init(upstreamSockets: 76, closeWaitSockets: 26),
            at: now.addingTimeInterval(20), tunnelIsSwitching: false
        ))
    }

    func testTunnelReconnectOnlyAfterRecentUnexpectedFailure() {
        var policy = TunnelAutoReconnectPolicy()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(policy.mayRetry(now: now, failureAt: nil, explicitDisconnect: false))
        XCTAssertFalse(policy.mayRetry(now: now, failureAt: now, explicitDisconnect: true))
        XCTAssertFalse(policy.mayRetry(now: now, failureAt: now.addingTimeInterval(-60), explicitDisconnect: false))
        XCTAssertTrue(policy.mayRetry(now: now, failureAt: now.addingTimeInterval(-2), explicitDisconnect: false))
        XCTAssertTrue(policy.mayRetry(now: now.addingTimeInterval(5), failureAt: now, explicitDisconnect: false))
        XCTAssertTrue(policy.mayRetry(now: now.addingTimeInterval(10), failureAt: now, explicitDisconnect: false))
        XCTAssertFalse(policy.mayRetry(now: now.addingTimeInterval(15), failureAt: now, explicitDisconnect: false))
        XCTAssertTrue(policy.mayRetry(now: now.addingTimeInterval(650), failureAt: now.addingTimeInterval(649), explicitDisconnect: false))
    }

    func testClockRollbackPreservesShortCooldownButResetsLongStall() {
        var policy = ConnectionPressurePolicy()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let overload = ConnectionPressurePolicy.Sample(upstreamSockets: 180, closeWaitSockets: 60)
        XCTAssertTrue(policy.shouldRecover(sample: overload, at: start, tunnelIsSwitching: false))
        // A small negative clock adjustment must not cause recovery thrash.
        XCTAssertFalse(policy.shouldRecover(sample: overload,
                                            at: start.addingTimeInterval(-30),
                                            tunnelIsSwitching: false))
        // A one-hour backwards jump cannot leave sockets accumulating for an hour.
        let corrected = start.addingTimeInterval(-3600)
        XCTAssertTrue(policy.shouldRecover(sample: overload,
                                           at: corrected, tunnelIsSwitching: false))
        XCTAssertFalse(policy.shouldRecover(sample: overload,
                                            at: corrected.addingTimeInterval(10),
                                            tunnelIsSwitching: false))
        XCTAssertTrue(policy.shouldRecover(sample: overload,
                                           at: corrected.addingTimeInterval(121),
                                           tunnelIsSwitching: false))
    }

    func testAutoReconnectBudgetSurvivesClockCorrection() {
        var policy = TunnelAutoReconnectPolicy()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for offset in 0..<3 {
            let at = start.addingTimeInterval(Double(offset))
            XCTAssertTrue(policy.mayRetry(now: at, failureAt: at, explicitDisconnect: false))
        }
        // A small rollback retains the cap to prevent a storm.
        let smallRollback = start.addingTimeInterval(-30)
        XCTAssertFalse(policy.mayRetry(now: smallRollback, failureAt: smallRollback,
                                       explicitDisconnect: false))
        // Attempts far in the future are invalid after a large clock correction.
        let corrected = start.addingTimeInterval(-3600)
        XCTAssertTrue(policy.mayRetry(now: corrected, failureAt: corrected,
                                      explicitDisconnect: false))
        XCTAssertFalse(policy.mayRetry(now: corrected, failureAt: corrected,
                                       explicitDisconnect: true))
    }

    func testSwitchingSuppressesRecycle() {
        var policy = ConnectionPressurePolicy()
        XCTAssertFalse(policy.shouldRecover(
            sample: .init(upstreamSockets: 200, closeWaitSockets: 180),
            at: Date(), tunnelIsSwitching: true
        ))
    }
}
