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
        XCTAssertTrue(policy.shouldRecover(sample: sample, at: start.addingTimeInterval(30), tunnelIsSwitching: false))
        XCTAssertFalse(policy.shouldRecover(sample: sample, at: start.addingTimeInterval(60), tunnelIsSwitching: false))
        XCTAssertTrue(policy.shouldRecover(sample: sample, at: start.addingTimeInterval(931), tunnelIsSwitching: false))
    }
    func testHardLimitTriggersImmediately() {
        var policy = ConnectionPressurePolicy()
        XCTAssertTrue(policy.shouldRecover(
            sample: .init(upstreamSockets: 160, closeWaitSockets: 0),
            at: Date(), tunnelIsSwitching: false
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
