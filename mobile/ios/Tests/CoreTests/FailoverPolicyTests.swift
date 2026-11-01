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

    func testLargePaidProxyListHasBoundedConnectionAttempts() {
        let ids = (0..<200).map { _ in UUID() }
        let ranked = FailoverPolicy().connectionCandidates(
            profileIDs: ids, primaryID: ids[100], lastSuccessfulID: ids[150],
            recentlyFailedID: ids[50], latencies: [ids[180]: 23, ids[190]: 45]
        )
        XCTAssertEqual(ranked.count, 6)
        XCTAssertEqual(ranked.prefix(4), [ids[100], ids[150], ids[180], ids[190]])
        XCTAssertFalse(ranked.contains(ids[50]))
    }

    func testConnectionMonitoringReducesProbeRateWithoutSingleFailureFlapping() {
        let policy = FailoverPolicy()
        XCTAssertEqual(policy.tuning.healthInterval, 10)
        XCTAssertFalse(policy.failureConfirmed(1))
        XCTAssertTrue(policy.failureConfirmed(2))
    }

    func testFailedPrimaryRecheckIsThrottledIndependently() {
        let now = Date()
        let policy = FailoverPolicy()
        XCTAssertFalse(policy.shouldProbePrimary(now: now, lastAttempt: nil,
            lastSwitch: now.addingTimeInterval(-10)))
        XCTAssertTrue(policy.shouldProbePrimary(now: now, lastAttempt: nil,
            lastSwitch: now.addingTimeInterval(-30)))
        XCTAssertFalse(policy.shouldProbePrimary(now: now,
            lastAttempt: now.addingTimeInterval(-10), lastSwitch: now.addingTimeInterval(-30)))
        XCTAssertTrue(policy.shouldProbePrimary(now: now,
            lastAttempt: now.addingTimeInterval(-31), lastSwitch: now.addingTimeInterval(-35)))
    }

    func testRestorePolicyHonorsCooldown() {
        let a = UUID(), b = UUID()
        XCTAssertFalse(FailoverPolicy().shouldRestorePrimary(
            policy: .returnToPrimary, currentID: b, primaryID: a,
            primaryAvailable: true, now: Date(), lastSwitch: Date()
        ))
    }
}
