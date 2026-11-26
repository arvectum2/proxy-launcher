import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

/// Local fake-private-database rehearsal. NOT a two-device CloudKit acceptance.
final class ExclusionCloudTwoDeviceSimulationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private enum Conflict: Error { case staleLocal, staleRemote, concurrentWrite }

    private struct Record {
        let id: String
        let tag: String
        let data: Data
    }
    private struct Pending {
        let tag: String?
        let recordID: String?
        let data: Data
    }
    private struct FakePrivateDatabase {
        var stored: Record?
        var serial = 0

        func preview() -> Record? { stored }

        func prepare(local: [String], approved: [String], reviewed: Record?,
                     deviceID: String, at now: Date) throws -> Pending {
            guard ExclusionSyncContract.localUnchanged(
                previewed: approved, current: local) else { throw Conflict.staleLocal }
            var revision = 1
            if let live = stored {
                guard let reviewed, reviewed.id == live.id,
                      let approvedSnapshot = try? ExclusionSyncContract.decode(reviewed.data, now: now),
                      let liveSnapshot = try? ExclusionSyncContract.decode(live.data, now: now),
                      ExclusionSyncContract.remoteUnchanged(
                        previewed: approvedSnapshot, current: liveSnapshot,
                        previewTag: reviewed.tag, currentTag: live.tag)
                else { throw Conflict.staleRemote }
                revision = liveSnapshot.revision + 1
            } else if reviewed != nil {
                throw Conflict.staleRemote
            }
            return Pending(tag: stored?.tag, recordID: stored?.id,
                           data: try ExclusionSyncContract.encode(
                            localDomains: approved, deviceID: deviceID,
                            revision: revision, at: now))
        }

        mutating func commit(_ pending: Pending) throws {
            if let current = stored {
                guard current.id == pending.recordID,
                      current.tag == pending.tag else { throw Conflict.concurrentWrite }
            } else if pending.tag != nil {
                throw Conflict.concurrentWrite
            }
            serial += 1
            stored = Record(id: "manual-exclusions.v1",
                            tag: "version-\(serial)", data: pending.data)
        }

        func mayApply(reviewed: Record?, approvedLocal: [String],
                      liveLocal: [String], at now: Date) -> Bool {
            guard ExclusionSyncContract.localUnchanged(
                previewed: approvedLocal, current: liveLocal),
                  let reviewed, let live = stored,
                  reviewed.id == live.id,
                  let original = try? ExclusionSyncContract.decode(reviewed.data, now: now),
                  let latest = try? ExclusionSyncContract.decode(live.data, now: now)
            else { return false }
            return ExclusionSyncContract.remoteUnchanged(
                previewed: original, current: latest,
                previewTag: reviewed.tag, currentTag: live.tag)
        }
    }

    private func publish(_ list: [String], device: String,
                         cloud: inout FakePrivateDatabase) throws {
        let plan = try cloud.prepare(local: list, approved: list,
                                     reviewed: cloud.preview(), deviceID: device, at: now)
        try cloud.commit(plan)
    }

    func testConcurrentFirstUploadDoesNotOverwriteOtherDevice() throws {
        var cloud = FakePrivateDatabase()
        let a = try cloud.prepare(local: ["a.example"], approved: ["a.example"],
                                  reviewed: nil, deviceID: "iphone_a", at: now)
        let b = try cloud.prepare(local: ["b.example"], approved: ["b.example"],
                                  reviewed: nil, deviceID: "iphone_b", at: now)
        try cloud.commit(a)
        XCTAssertThrowsError(try cloud.commit(b))
        XCTAssertEqual(try ExclusionSyncContract.decode(
            XCTUnwrap(cloud.stored?.data), now: now).manualDomains, ["a.example"])
    }

    func testRemoteEditAfterReviewBlocksSecondDeviceUploadAndApply() throws {
        var cloud = FakePrivateDatabase()
        try publish(["old.example"], device: "iphone_a", cloud: &cloud)
        let previewB = cloud.preview()
        try publish(["new.example"], device: "iphone_a", cloud: &cloud)
        XCTAssertThrowsError(try cloud.prepare(
            local: ["b.example"], approved: ["b.example"], reviewed: previewB,
            deviceID: "iphone_b", at: now))
        XCTAssertFalse(cloud.mayApply(reviewed: previewB,
                                     approvedLocal: ["local.example"],
                                     liveLocal: ["local.example"], at: now))
    }

    func testConcurrentModificationBetweenPreflightAndCommitBlocksWrite() throws {
        var cloud = FakePrivateDatabase()
        try publish(["start.example"], device: "iphone_a", cloud: &cloud)
        let pendingB = try cloud.prepare(
            local: ["b.example"], approved: ["b.example"],
            reviewed: cloud.preview(), deviceID: "iphone_b", at: now)
        try publish(["a.example"], device: "iphone_a", cloud: &cloud)
        XCTAssertThrowsError(try cloud.commit(pendingB))
        XCTAssertEqual(try ExclusionSyncContract.decode(
            XCTUnwrap(cloud.stored?.data), now: now).manualDomains, ["a.example"])
    }

    func testLocalEditAndRemoteDeletionInvalidateReview() throws {
        var cloud = FakePrivateDatabase()
        try publish(["remote.example"], device: "iphone_a", cloud: &cloud)
        let review = cloud.preview()
        XCTAssertTrue(cloud.mayApply(reviewed: review, approvedLocal: ["local.example"],
                                     liveLocal: ["LOCAL.EXAMPLE"], at: now))
        XCTAssertFalse(cloud.mayApply(reviewed: review, approvedLocal: ["local.example"],
                                      liveLocal: ["edited.example"], at: now))
        XCTAssertThrowsError(try cloud.prepare(
            local: ["edited.example"], approved: ["local.example"],
            reviewed: review, deviceID: "iphone_b", at: now))
        cloud.stored = nil
        XCTAssertFalse(cloud.mayApply(reviewed: review,
                                     approvedLocal: ["local.example"],
                                     liveLocal: ["local.example"], at: now))
    }

    func testNewTagWithIdenticalPayloadStillBlocksOldReview() throws {
        var cloud = FakePrivateDatabase()
        try publish(["same.example"], device: "iphone_a", cloud: &cloud)
        let old = try XCTUnwrap(cloud.preview())
        cloud.stored = Record(id: old.id, tag: "version-external", data: old.data)
        XCTAssertFalse(cloud.mayApply(reviewed: old,
                                     approvedLocal: [], liveLocal: [], at: now))
        XCTAssertThrowsError(try cloud.prepare(
            local: [], approved: [], reviewed: old,
            deviceID: "iphone_b", at: now))
    }

    func testCorruptRemotePayloadFailsClosedWithoutLocalMutation() throws {
        var cloud = FakePrivateDatabase()
        try publish(["before.example"], device: "iphone_a", cloud: &cloud)
        let reviewed = cloud.preview()
        cloud.stored = Record(id: "manual-exclusions.v1",
                              tag: "invalid-tag", data: Data([0x00, 0x01, 0xff]))
        XCTAssertFalse(cloud.mayApply(
            reviewed: reviewed, approvedLocal: [], liveLocal: [], at: now))
        XCTAssertThrowsError(try cloud.prepare(
            local: [], approved: [], reviewed: reviewed,
            deviceID: "iphone_b", at: now))
    }
}
