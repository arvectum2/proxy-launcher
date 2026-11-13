import Foundation

/// Future iCloud private-database payload. Only manual exclusions may be
/// represented here; never synchronize Keychain, proxy credentials, live
/// Smart3 evidence, derived route IPs or VPN settings via this contract.
struct ManualExclusionSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let deviceID: String
    let revision: Int
    let generatedAt: Date
    let manualDomains: [String]
}

struct ManualExclusionChange: Equatable {
    let toAdd: [String]
    let toRemove: [String]
}

enum ExclusionSyncError: Error, Equatable {
    case oversized, invalid, unsafe
}

enum ExclusionSyncContract {
    static let maxBytes = 16 * 1024
    /// Keep cloud revision increments inside a portable, bounded range.
    static let maxRevision = 2_147_483_646

    static func encode(localDomains: [String], deviceID: String, revision: Int,
                       at date: Date = Date()) throws -> Data {
        guard validDeviceID(deviceID), (1...maxRevision).contains(revision) else {
            throw ExclusionSyncError.invalid
        }
        let normalized = try SiteExclusionPolicy.normalizeAll(localDomains)
        let snapshot = ManualExclusionSnapshot(schemaVersion: 1, deviceID: deviceID,
                                               revision: revision, generatedAt: date,
                                               manualDomains: normalized)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(snapshot)
        guard bytes.count <= maxBytes else { throw ExclusionSyncError.oversized }
        return bytes
    }

    static func decode(_ bytes: Data, now: Date = Date()) throws -> ManualExclusionSnapshot {
        guard bytes.count <= maxBytes else { throw ExclusionSyncError.oversized }
        guard let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(root.keys) == Set(["schemaVersion", "deviceID", "revision", "generatedAt", "manualDomains"])
        else { throw ExclusionSyncError.invalid }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(ManualExclusionSnapshot.self, from: bytes),
              snapshot.schemaVersion == 1, validDeviceID(snapshot.deviceID),
              (1...maxRevision).contains(snapshot.revision),
              snapshot.generatedAt <= now.addingTimeInterval(300),
              snapshot.manualDomains.count <= SiteExclusionPolicy.maxEntries
        else { throw ExclusionSyncError.invalid }
        guard let normalized = try? SiteExclusionPolicy.normalizeAll(snapshot.manualDomains),
              normalized == snapshot.manualDomains else { throw ExclusionSyncError.unsafe }
        return snapshot
    }

    /// Diff only: a remote update may never silently enable or remove DIRECT
    /// routes; user approval and existing VPN rollback logic are separate.
    static func preview(local: [String], remote: ManualExclusionSnapshot) throws -> ManualExclusionChange {
        let localSet = Set(try SiteExclusionPolicy.normalizeAll(local))
        let remoteSet = Set(remote.manualDomains)
        guard remoteSet.count == remote.manualDomains.count,
              (try? SiteExclusionPolicy.normalizeAll(remote.manualDomains)) == remote.manualDomains
        else { throw ExclusionSyncError.unsafe }
        return ManualExclusionChange(toAdd: remoteSet.subtracting(localSet).sorted(),
                                     toRemove: localSet.subtracting(remoteSet).sorted())
    }

    /// A user-approved preview is invalidated if the manual list changes.
    /// Reject malformed/corrupted snapshot data rather than "normalizing"
    /// it silently into a different approved list.
    static func localUnchanged(previewed: [String], current: [String]) -> Bool {
        guard let approved = try? SiteExclusionPolicy.normalizeAll(previewed),
              approved == previewed,
              let live = try? SiteExclusionPolicy.normalizeAll(current)
        else { return false }
        return live == approved
    }

    /// The server may have changed on another device after the user's review.
    /// A same-revision payload with a new CloudKit record tag is still stale.
    /// Both payload and nonempty change tag must match the approved preview.
    static func remoteUnchanged(previewed: ManualExclusionSnapshot, current: ManualExclusionSnapshot,
                                previewTag: String?, currentTag: String?) -> Bool {
        guard let previewTag, !previewTag.isEmpty,
              let currentTag, !currentTag.isEmpty
        else { return false }
        return previewTag == currentTag && previewed == current
    }

    private static func validDeviceID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 64 && id.utf8.allSatisfy {
            ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) ||
            ($0 >= 48 && $0 <= 57) || $0 == 45 || $0 == 95
        }
    }
}
