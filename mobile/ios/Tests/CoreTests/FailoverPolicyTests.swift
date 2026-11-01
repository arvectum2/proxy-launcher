import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class FailoverPolicyTests: XCTestCase {
    func testCandidateOrderPrefersPrimaryThenLastSuccessful() {
        let a = UUID(), b = UUID(), c = UUID()
        let ordered = FailoverPolicy().orderCandidates(
            profileIDs: [a, b, c], primaryID: b, lastSuccessfulID: c, recentlyFailedID: nil
        )
        XCTAssertEqual(ordered, [b, c, a])
    }

    func testRecentlyFailedMovesToEnd() {
        let a = UUID(), b = UUID(), c = UUID()
        let ordered = FailoverPolicy().orderCandidates(
            profileIDs: [a, b, c], primaryID: a, lastSuccessfulID: b, recentlyFailedID: a
        )
        XCTAssertEqual(ordered, [b, c, a])
    }

    func testHealthyBackupsUseMeasuredSpeedButRespectPrimaryAndFailure() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let policy = FailoverPolicy()
        XCTAssertEqual(policy.orderCandidates(profileIDs: [a,b,c,d], primaryID: a,
            lastSuccessfulID: b, recentlyFailedID: nil, latencies: [c: 120, d: 35]), [a,b,d,c])
        XCTAssertEqual(policy.orderCandidates(profileIDs: [a,b,c,d], primaryID: a,
            lastSuccessfulID: b, recentlyFailedID: d, latencies: [c: 120, d: 35]), [a,b,c,d])
    }

    func testRestorePolicyHonorsCooldown() {
        let a = UUID(), b = UUID()
        XCTAssertFalse(FailoverPolicy().shouldRestorePrimary(
            policy: .returnToPrimary, currentID: b, primaryID: a,
            primaryAvailable: true, now: Date(), lastSwitch: Date()
        ))
    }
}
