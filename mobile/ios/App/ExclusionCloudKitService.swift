import CloudKit
import Foundation

enum ExclusionCloudKitFailure: Error {
    case unavailable
    case invalidPayload
    case requiresRemotePreview
    case changedOnServer
}

/// iCloud sync of manual hostname exclusions only. Never transports Keychain,
/// password, smart dependency graph, observed IPs, or live VPN preferences.
/// Calls are made only following an explicit user action in the opt-in UI.
@MainActor
final class ExclusionCloudKitService {
    static let containerID = "iCloud.ru.arvectum.proxylauncher.ios"
    private static let recordType = "APLManualExclusions"
    private static let recordID = CKRecord.ID(recordName: "manual-exclusions.v1")
    private static let deviceIDKey = "manual_exclusion_cloud_device.v1"

    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }

    init() {
        container = CKContainer(identifier: Self.containerID)
    }

    func requireAvailableAccount() async throws {
        let result: (CKAccountStatus, Error?) = await withCheckedContinuation { continuation in
            container.accountStatus { status, error in
                continuation.resume(returning: (status, error))
            }
        }
        guard result.1 == nil, result.0 == .available else {
            throw ExclusionCloudKitFailure.unavailable
        }
    }

    /// Returns the server record for optimistic concurrency control. A missing
    /// record is distinct from any error and must never be inferred from a
    /// failed request.
    func previewRemote(now: Date = Date()) async throws -> (ManualExclusionSnapshot, CKRecord)? {
        try await requireAvailableAccount()
        let record: CKRecord
        do {
            record = try await database.record(for: Self.recordID)
        } catch {
            if (error as? CKError)?.code == .unknownItem { return nil }
            throw error
        }
        guard record.recordType == Self.recordType,
              let data = record["payload"] as? Data else {
            throw ExclusionCloudKitFailure.invalidPayload
        }
        let snapshot = try ExclusionSyncContract.decode(data, now: now)
        return (snapshot, record)
    }

    /// A previously previewed server record is required to overwrite any
    /// nonempty remote state. CKModifyRecords.ifServerRecordUnchanged prevents
    /// silent last-writer-wins overwrites after the user's confirmation.
    func upload(manualDomains: [String], expectedRemote: CKRecord?,
                observedRemoteWasAbsent: Bool) async throws -> ManualExclusionSnapshot {
        try await requireAvailableAccount()
        let live = try await previewRemote()
        let record: CKRecord
        let revision: Int
        if let (currentSnapshot, currentRecord) = live {
            // Record versions alone are insufficient as a review receipt:
            // require the same exact server payload that the user previewed.
            // Empty change tags, missing/corrupt payloads or mismatched types
            // must never authorize an overwrite of an existing cloud record.
            guard let expectedRemote,
                  expectedRemote.recordID == currentRecord.recordID,
                  expectedRemote.recordType == Self.recordType,
                  let reviewedBytes = expectedRemote["payload"] as? Data,
                  let reviewedSnapshot = try? ExclusionSyncContract.decode(reviewedBytes),
                  ExclusionSyncContract.remoteUnchanged(
                    previewed: reviewedSnapshot, current: currentSnapshot,
                    previewTag: expectedRemote.recordChangeTag,
                    currentTag: currentRecord.recordChangeTag) else {
                throw ExclusionCloudKitFailure.requiresRemotePreview
            }
            record = currentRecord
            revision = currentSnapshot.revision + 1
        } else {
            guard observedRemoteWasAbsent, expectedRemote == nil else {
                throw ExclusionCloudKitFailure.changedOnServer
            }
            record = CKRecord(recordType: Self.recordType, recordID: Self.recordID)
            revision = 1
        }
        let data = try ExclusionSyncContract.encode(localDomains: manualDomains,
                                                     deviceID: deviceID(), revision: revision)
        let snapshot = try ExclusionSyncContract.decode(data)
        record["payload"] = data as NSData
        let changes = try await database.modifyRecords(
            saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        guard let saved = changes.saveResults[record.recordID] else {
            throw ExclusionCloudKitFailure.changedOnServer
        }
        do { _ = try saved.get() }
        catch { throw ExclusionCloudKitFailure.changedOnServer }
        return snapshot
    }

    private func deviceID() -> String {
        let defaults = UserDefaults(suiteName: AppShared.defaultsSuite)
        if let existing = defaults?.string(forKey: Self.deviceIDKey),
           !existing.isEmpty { return existing }
        let created = UUID().uuidString.lowercased()
        defaults?.set(created, forKey: Self.deviceIDKey)
        return created
    }
}
