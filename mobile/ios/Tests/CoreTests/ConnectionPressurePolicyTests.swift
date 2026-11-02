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

    func testSwitchingSuppressesRecycle() {
        var policy = ConnectionPressurePolicy()
        XCTAssertFalse(policy.shouldRecover(
            sample: .init(upstreamSockets: 200, closeWaitSockets: 180),
            at: Date(), tunnelIsSwitching: true
        ))
    }
}
