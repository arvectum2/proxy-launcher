import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ExclusionSyncContractTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDeterministicManualOnlyRoundTrip() throws {
        let encoded = try ExclusionSyncContract.encode(
            localDomains: ["www.gosuslugi.ru", "Example.COM", "example.com"],
            deviceID: "iphone_1", revision: 3, at: now)
        let snapshot = try ExclusionSyncContract.decode(encoded, now: now)
        XCTAssertEqual(snapshot.manualDomains, ["example.com", "www.gosuslugi.ru"])
        XCTAssertEqual(snapshot.revision, 3)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("password"))
    }

    func testRemoteRulesAlwaysBecomePreviewOnly() throws {
        let encoded = try ExclusionSyncContract.encode(
            localDomains: ["new.example"], deviceID: "device_2", revision: 1, at: now)
        let remote = try ExclusionSyncContract.decode(encoded, now: now)
        let change = try ExclusionSyncContract.preview(local: ["existing.example"], remote: remote)
        XCTAssertEqual(change.toAdd, ["new.example"])
        XCTAssertEqual(change.toRemove, ["existing.example"])
    }

    func testRejectsUntrustedFieldsStaleSchemaAndMalformedEntries() throws {
        let encoded = try ExclusionSyncContract.encode(
            localDomains: ["example.com"], deviceID: "phone", revision: 1, at: now)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        root["password"] = "secret"
        XCTAssertThrowsError(try ExclusionSyncContract.decode(
            JSONSerialization.data(withJSONObject: root), now: now))
        root.removeValue(forKey: "password")
        root["schemaVersion"] = 99
        XCTAssertThrowsError(try ExclusionSyncContract.decode(
            JSONSerialization.data(withJSONObject: root), now: now))
        root["schemaVersion"] = 1
        root["manualDomains"] = ["*.example.com"]
        XCTAssertThrowsError(try ExclusionSyncContract.decode(
            JSONSerialization.data(withJSONObject: root), now: now))
    }

    func testRevisionOverflowIsRejectedBeforeCloudUpload() throws {
        XCTAssertThrowsError(try ExclusionSyncContract.encode(
            localDomains: ["example.com"], deviceID: "phone",
            revision: Int.max, at: now))
        XCTAssertThrowsError(try ExclusionSyncContract.encode(
            localDomains: ["example.com"], deviceID: "phone",
            revision: 0, at: now))
    }

    func testRejectsOversizeInvalidDeviceAndFutureTimestamp() throws {
        XCTAssertThrowsError(try ExclusionSyncContract.decode(Data(repeating: 65, count: 16_385)))
        XCTAssertThrowsError(try ExclusionSyncContract.encode(
            localDomains: [], deviceID: "../phone", revision: 1, at: now))
        let future = try ExclusionSyncContract.encode(
            localDomains: [], deviceID: "phone", revision: 1, at: now.addingTimeInterval(1_000))
        XCTAssertThrowsError(try ExclusionSyncContract.decode(future, now: now))
    }
}
