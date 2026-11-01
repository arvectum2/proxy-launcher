import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProfileScanPolicyTests: XCTestCase {
    func testAutomaticChecksAtMostThreeHighPriorityProfiles() {
        let ids = (0..<100).map { _ in UUID() }
        let batch = ProfileScanPolicy().batch(ids: ids, selectedID: ids[11], primaryID: ids[12], favorites: [ids[20]])
        XCTAssertEqual(batch, [ids[11], ids[12], ids[20]])
    }

    func testManualBatchesCoverListWithoutRepeatingSameEntry() {
        let ids = (0..<23).map { _ in UUID() }
        let policy = ProfileScanPolicy()
        let first = policy.batch(ids: ids, selectedID: nil, primaryID: nil, favorites: [], manualCursor: 0)
        let second = policy.batch(ids: ids, selectedID: nil, primaryID: nil, favorites: [], manualCursor: 10)
        let third = policy.batch(ids: ids, selectedID: nil, primaryID: nil, favorites: [], manualCursor: 20)
        XCTAssertEqual(first.count, 10)
        XCTAssertEqual(second.count, 10)
        XCTAssertEqual(Array(third.prefix(3)), Array(ids.suffix(3)))
        XCTAssertEqual(Set(first + second + third), Set(ids))
    }

    func testCooldownAndEmptyProfiles() {
        let now = Date()
        let policy = ProfileScanPolicy()
        XCTAssertFalse(policy.permitted(now: now, lastScan: now.addingTimeInterval(-20), manual: false))
        XCTAssertTrue(policy.permitted(now: now, lastScan: now.addingTimeInterval(-20), manual: true))
        XCTAssertTrue(policy.batch(ids: [], selectedID: UUID(), primaryID: nil, favorites: []).isEmpty)
    }
}
