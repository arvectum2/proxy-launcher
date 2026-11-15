import Foundation

/// Metadata-only single-writer catalog. The app owns writes; the provider
/// reads the latest snapshot. Implementations must replace atomically and
/// may not report a failed write as a committed replacement.
protocol NativeCredentialCatalogStorage {
    func load() throws -> Data?
    func replace(_ bytes: Data) throws
}

struct NativeCredentialCatalogReader {
    typealias Ref = NativeCredentialRecord.Reference
    struct Snapshot: Codable, Equatable {
        let version: Int
        var current: [Ref]
        var retired: [Ref]
        var selected: Ref?
        var pendingInsert: Ref?
        // Optional for backward compatibility with existing v1 snapshots.
        var pendingRestore: [Ref]?
        var hasPendingWrite: Bool { pendingInsert != nil || pendingRestore != nil }
        static let empty = Self(version:1,current:[],retired:[],selected:nil,pendingInsert:nil,pendingRestore:nil)
    }
    enum Failure: Error { case invalidCatalog, capacity, collision, missing, rollbackIncomplete }
    let storage: NativeCredentialCatalogStorage
    func snapshot() throws -> Snapshot {
        guard let data = try storage.load() else { return .empty }
        guard !data.isEmpty, data.count <= 32_768 else { throw Failure.invalidCatalog }
        let s = try JSONDecoder().decode(Snapshot.self,from:data)
        guard s.version == 1, s.current.count <= 32, s.retired.count <= 64,
              Set(s.current.map(\.profileID)).count == s.current.count,
              Set(s.retired).count == s.retired.count,
              Set(s.current).isDisjoint(with:Set(s.retired)),
              s.selected.map({s.current.contains($0)}) ?? true,
              s.pendingInsert.map({!s.current.contains($0) && !s.retired.contains($0)}) ?? true,
              validRestoreJournal(s) else { throw Failure.invalidCatalog }
        return s
    }
    private func validRestoreJournal(_ s: Snapshot) -> Bool {
        guard let refs=s.pendingRestore else {return true}
        let occupied=Set((s.current+s.retired).map(\.profileID))
        let ids=Set(refs.map(\.profileID))
        return s.pendingInsert == nil && !refs.isEmpty && refs.count <= 32-s.current.count && ids.count == refs.count && ids.isDisjoint(with:occupied)
    }
    func isSelected(_ ref: Ref) throws -> Bool {
        let s=try snapshot()
        return s.pendingRestore == nil && s.selected == ref
    }
    // Explicit call only from authorized export UI in the future. Reads exact
    // current revisions, not retired/pending entries, and rejects changed view.
    func currentRecordsForBackup(repository: NativeCredentialRepository) throws -> [NativeCredentialRecord] {
        let start=try snapshot()
        guard !start.hasPendingWrite else {throw Failure.rollbackIncomplete}
        let records=try start.current.map { ref in
            guard let record=try repository.read(ref) else {throw Failure.missing};return record
        }
        guard try snapshot() == start else {throw Failure.invalidCatalog}
        return records
    }
}

/// No active UI or migration. Single app writer; stop/authorization must be
/// coordinated before editing a live session. Catalog commit publishes the
/// new revision before old credentials can be retired, and failed cleanup
/// never makes an old revision current again.
@MainActor final class NativeCredentialCatalog {
    typealias Ref = NativeCredentialRecord.Reference
    typealias Snapshot = NativeCredentialCatalogReader.Snapshot
    typealias Failure = NativeCredentialCatalogReader.Failure
    let reader: NativeCredentialCatalogReader
    private let repository: NativeCredentialRepository
    private let legacyIDs: () throws -> Set<UUID>
    init(storage: NativeCredentialCatalogStorage, repository: NativeCredentialRepository, legacyIDs: @escaping () throws -> Set<UUID>) {
        reader = .init(storage:storage); self.repository = repository; self.legacyIDs = legacyIDs
    }
    func reviewState() throws -> (Snapshot, Set<UUID>) {
        (try reader.snapshot(),try legacyIDs())
    }
    private func publish(_ s: Snapshot) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(s)
        guard bytes.count <= 32_768 else { throw Failure.capacity }
        try reader.storage.replace(bytes)
    }
    func save(_ record: NativeCredentialRecord, select: Bool) throws {
        let ref = record.reference
        guard !(try legacyIDs()).contains(ref.profileID) else { throw Failure.collision }
        let original = try reader.snapshot()
        guard !original.hasPendingWrite else { throw Failure.rollbackIncomplete }
        var s = original
        guard !s.current.contains(ref), !s.retired.contains(ref) else { throw Failure.collision }
        if let index = s.current.firstIndex(where:{$0.profileID == ref.profileID}) {
            guard s.retired.count < 64 else { throw Failure.capacity }
            let old = s.current[index]; s.retired.append(old); s.current[index] = ref
            if s.selected == old { s.selected = nil }
        } else {
            guard s.current.count < 32 else { throw Failure.capacity }; s.current.append(ref)
        }
        if select { s.selected = ref }
        // Journal the exact intended revision before any credential write.
        // A crash can leave a pending entry, never an unknown record to sweep.
        guard try repository.read(ref) == nil else { throw Failure.collision }
        var journal = original; journal.pendingInsert = ref
        try publish(journal)
        do {
            try repository.insert(record)
            try publish(s)
        } catch {
            do { try reconcilePendingInsert() }
            catch { throw Failure.rollbackIncomplete }
            throw error
        }
    }
    /// Restore is additive and publishes all records in one atomic catalog
    /// update. The future caller must hold an exclusive VPN-start/write
    /// lease; `vpnInactive` is an injected independently observed guard,
    /// not an OS status check or a substitute for that lease.
    @discardableResult func restore(_ incoming: [NativeCredentialRecord],
                                    vpnInactive: () throws -> Bool) throws -> [Ref] {
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        let original=try reader.snapshot()
        guard !original.hasPendingWrite else {throw Failure.rollbackIncomplete}
        let legacy=try legacyIDs()
        let fresh=try NativeProfileBackupCodec.prepareRestore(incoming,existingNativeIDs:Set(original.current.map(\.profileID)),legacyIDs:legacy.union(original.retired.map(\.profileID)))
        let refs=fresh.map(\.reference)
        for ref in refs {guard try repository.read(ref) == nil else {throw Failure.collision}}
        guard try vpnInactive(), try reader.snapshot() == original, try legacyIDs() == legacy else {throw Failure.collision}
        var journal=original; journal.pendingRestore=refs
        try publish(journal)
        do {
            for record in fresh {
                guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
                try repository.insert(record)
            }
            guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
            guard try reader.snapshot() == journal, try legacyIDs() == legacy else {throw Failure.collision}
            for ref in refs {guard try repository.read(ref) != nil else {throw Failure.missing}}
            var committed=original; committed.current += refs
            try publish(committed)
            return refs
        } catch {
            // Exact journal owned by this writer only. Never touch committed
            // or retired records if catalog state unexpectedly changed.
            do {
                guard try reader.snapshot() == journal else {throw Failure.rollbackIncomplete}
                try reconcilePendingRestore(vpnInactive:vpnInactive)
            } catch {throw Failure.rollbackIncomplete}
            throw error
        }
    }
    /// Recover a crash before final publication. No imported record can be
    /// visible as current until the entire journal has committed.
    func reconcilePendingRestore(vpnInactive: () throws -> Bool) throws {
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        var s=try reader.snapshot()
        guard let refs=s.pendingRestore else {return}
        for ref in refs {
            guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
            _ = try repository.remove(ref)
        }
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        s.pendingRestore=nil;try publish(s)
    }
    func select(_ ref: Ref) throws {
        guard !(try legacyIDs()).contains(ref.profileID) else { throw Failure.collision }
        var s = try reader.snapshot()
        guard !s.hasPendingWrite else { throw Failure.rollbackIncomplete }
        guard s.current.contains(ref), try repository.read(ref) != nil else { throw Failure.missing }
        s.selected = ref; try publish(s)
    }
    func remove(_ ref: Ref) throws {
        var s = try reader.snapshot()
        guard !s.hasPendingWrite else { throw Failure.rollbackIncomplete }
        guard s.current.contains(ref) else { throw Failure.missing }
        guard s.retired.count < 64 else { throw Failure.capacity }
        s.current.removeAll{$0 == ref}; s.retired.append(ref)
        if s.selected == ref { s.selected = nil }
        try publish(s)
    }
    /// Recovery is safe after interruption at either side of record insertion.
    /// Never deletes any currently published or retired revision.
    func reconcilePendingInsert() throws {
        var s = try reader.snapshot()
        guard let ref = s.pendingInsert else { return }
        _ = try repository.remove(ref)
        s.pendingInsert = nil; try publish(s)
    }
    /// Delete only explicitly recorded retired revisions. Retry is idempotent
    /// if a crash happens after item deletion but before catalog publication.
    func reconcileRetired() throws {
        var s = try reader.snapshot()
        guard !s.hasPendingWrite else { throw Failure.rollbackIncomplete }
        for ref in s.retired {
            _ = try repository.remove(ref)
            s.retired.removeAll{$0 == ref}; try publish(s)
        }
    }
}
