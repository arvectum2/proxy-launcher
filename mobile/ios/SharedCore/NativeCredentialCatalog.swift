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
        var version: Int
        var current: [Ref]
        var retired: [Ref]
        var selected: Ref?
        // Legacy v1 snapshots may omit this. Such selection is display-only
        // until the user explicitly selects a profile again.
        var selectionNonce: UUID? = nil
        // Every successful publication (including rollback) gets a fresh
        // epoch. Older v1/v2 snapshots may omit it. Not cross-process CAS.
        var mutationEpoch: UUID? = nil
        var pendingInsert: Ref?
        // Optional for backward compatibility with existing v1 snapshots.
        var pendingRestore: [Ref]?
        var hasPendingWrite: Bool { pendingInsert != nil || pendingRestore != nil }
        static let empty = Self(version:2,current:[],retired:[],selected:nil,pendingInsert:nil,pendingRestore:nil)
    }
    enum Failure: Error { case invalidCatalog, capacity, collision, missing, rollbackIncomplete, migrationRequired }
    let storage: NativeCredentialCatalogStorage
    func snapshot() throws -> Snapshot {
        guard let data = try storage.load() else { return .empty }
        guard !data.isEmpty, data.count <= 32_768 else { throw Failure.invalidCatalog }
        let s = try JSONDecoder().decode(Snapshot.self,from:data)
        guard (s.version == 1 || s.version == 2), s.current.count <= 32, s.retired.count <= 64,
              Set(s.current.map(\.profileID)).count == s.current.count,
              Set(s.retired).count == s.retired.count,
              Set(s.current).isDisjoint(with:Set(s.retired)),
              s.selected.map({s.current.contains($0)}) ?? true,
              (s.selectionNonce == nil || s.selected != nil),
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
    func selectionAuthority(_ ref: Ref) throws -> UUID? {
        let s=try snapshot()
        guard s.version == 2, !s.hasPendingWrite, s.selected==ref else {return nil}
        return s.selectionNonce
    }
    func authorizes(_ binding: NativeCredentialHandoff.Binding) throws -> Bool {
        try selectionAuthority(binding.reference) == binding.selectionNonce
    }
    // Explicit call only from authorized export UI in the future. Reads exact
    // current revisions, not retired/pending entries, and rejects changed view.
    func currentRecordsForBackup(repository: NativeCredentialRepository) throws -> [NativeCredentialRecord] {
        let start=try snapshot()
        guard start.version == 2 else {throw Failure.migrationRequired}
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
    func encryptedBackup(password:String,expected:Snapshot,expectedLegacy:Set<UUID>,vpnInactive:()throws->Bool)throws->Data {
        guard try vpnInactive(),try reader.snapshot()==expected,try legacyIDs()==expectedLegacy else{throw Failure.rollbackIncomplete}
        guard Set(expected.current.map(\.profileID)).isDisjoint(with:expectedLegacy) else{throw Failure.collision}
        let records=try reader.currentRecordsForBackup(repository:repository)
        let result=try NativeProfileBackupCodec.seal(records,password:password)
        guard try vpnInactive(),try reader.snapshot()==expected,try legacyIDs()==expectedLegacy else{throw Failure.rollbackIncomplete}
        return result
    }
    /// Read exactly the explicitly selected current WG/AWG revision. This
    /// returns only route metadata, never engine configuration or a ticket.
    func selectedRouteForReview(_ ref:Ref,expected:Snapshot,expectedLegacy:Set<UUID>,vpnInactive:()throws->Bool)throws->NativeTunnelRoutePlan {
        guard expected.version==2,!expected.hasPendingWrite,expected.selected==ref,expected.selectionNonce != nil,expected.current.contains(ref),!expectedLegacy.contains(ref.profileID),ref.kind != .vlessReality else{throw Failure.invalidCatalog}
        guard try vpnInactive(),try reader.snapshot()==expected,try legacyIDs()==expectedLegacy else{throw Failure.rollbackIncomplete}
        guard let record=try repository.read(ref) else{throw Failure.missing}
        guard case .wireGuard(let plan)=try record.compile().1 else{throw Failure.invalidCatalog}
        guard try vpnInactive(),try reader.snapshot()==expected,try legacyIDs()==expectedLegacy else{throw Failure.rollbackIncomplete}
        return plan
    }
    func reviewState() throws -> (Snapshot, Set<UUID>) {
        (try reader.snapshot(),try legacyIDs())
    }
    /// The v1 reader could ignore new fields. Upgrade explicitly before any
    /// further mutation. Preserve all exact references and unfinished journals;
    /// discard old selection authority, require deliberate reselection.
    /// Caller must hold exclusive app-writer/OS-start coordination.
    func migrateLegacyForValidation(vpnInactive: () throws -> Bool) throws {
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        let old=try reader.snapshot()
        guard old.version == 1 else {return}
        var upgraded=old;upgraded.version=2;upgraded.selectionNonce=nil
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        guard try reader.snapshot()==old else {throw Failure.rollbackIncomplete}
        try publish(&upgraded)
    }
    private func writableSnapshot() throws -> Snapshot {
        let s=try reader.snapshot()
        guard s.version==2 else {throw Failure.migrationRequired}
        return s
    }
    private func publish(_ s: inout Snapshot) throws {
        guard s.version==2 else {throw Failure.migrationRequired}
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var next=s;next.mutationEpoch=UUID()
        let bytes = try encoder.encode(next)
        guard bytes.count <= 32_768 else { throw Failure.capacity }
        try reader.storage.replace(bytes)
        s=next
    }
    func save(_ record: NativeCredentialRecord, select: Bool) throws {
        let ref = record.reference
        let legacy = try legacyIDs()
        guard !legacy.contains(ref.profileID) else { throw Failure.collision }
        let original = try writableSnapshot()
        guard !original.hasPendingWrite else { throw Failure.rollbackIncomplete }
        var s = original
        guard !s.current.contains(ref), !s.retired.contains(ref) else { throw Failure.collision }
        if let index = s.current.firstIndex(where:{$0.profileID == ref.profileID}) {
            guard s.retired.count < 64 else { throw Failure.capacity }
            let old = s.current[index]; s.retired.append(old); s.current[index] = ref
            if s.selected == old { s.selected = nil; s.selectionNonce = nil }
        } else {
            guard s.current.count < 32 else { throw Failure.capacity }; s.current.append(ref)
        }
        if select { s.selected = ref; s.selectionNonce = UUID() }
        // Journal the exact intended revision before any credential write.
        // A crash can leave a pending entry, never an unknown record to sweep.
        guard try repository.read(ref) == nil, try legacyIDs() == legacy, try reader.snapshot() == original else { throw Failure.collision }
        var journal = original; journal.pendingInsert = ref
        try publish(&journal)
        do {
            try repository.insert(record)
            guard let stored = try repository.read(ref), try stored.encoded() == record.encoded() else {throw Failure.missing}
            guard try legacyIDs() == legacy, try reader.snapshot() == journal else {throw Failure.rollbackIncomplete}
            try publish(&s)
        } catch {
            do {
                guard try reader.snapshot() == journal else {throw Failure.rollbackIncomplete}
                try reconcilePendingInsert()
            }
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
        let original=try writableSnapshot()
        guard !original.hasPendingWrite else {throw Failure.rollbackIncomplete}
        let legacy=try legacyIDs()
        let fresh=try NativeProfileBackupCodec.prepareRestore(incoming,existingNativeIDs:Set(original.current.map(\.profileID)),legacyIDs:legacy.union(original.retired.map(\.profileID)))
        let refs=fresh.map(\.reference)
        for ref in refs {guard try repository.read(ref) == nil else {throw Failure.collision}}
        guard try vpnInactive(), try reader.snapshot() == original, try legacyIDs() == legacy else {throw Failure.collision}
        var journal=original; journal.pendingRestore=refs
        try publish(&journal)
        do {
            for record in fresh {
                guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
                guard try legacyIDs() == legacy, try reader.snapshot() == journal else {throw Failure.rollbackIncomplete}
                try repository.insert(record)
            }
            guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
            guard try reader.snapshot() == journal, try legacyIDs() == legacy else {throw Failure.collision}
            for record in fresh {
                guard let stored = try repository.read(record.reference), try stored.encoded() == record.encoded() else {throw Failure.missing}
            }
            guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
            guard try legacyIDs() == legacy, try reader.snapshot() == journal else {throw Failure.rollbackIncomplete}
            var committed=original; committed.current += refs
            try publish(&committed)
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
        var s=try writableSnapshot()
        guard let refs=s.pendingRestore else {return}
        let journal=s
        for ref in refs {
            guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
            guard try reader.snapshot() == journal else {throw Failure.rollbackIncomplete}
            _ = try repository.remove(ref)
        }
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        guard try reader.snapshot() == journal else {throw Failure.rollbackIncomplete}
        s.pendingRestore=nil;try publish(&s)
    }
    func select(_ ref: Ref, vpnInactive: () throws -> Bool = {true}) throws {
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        let legacy=try legacyIDs()
        guard !legacy.contains(ref.profileID) else { throw Failure.collision }
        var s = try writableSnapshot()
        guard !s.hasPendingWrite else { throw Failure.rollbackIncomplete }
        guard s.current.contains(ref), try repository.read(ref) != nil else { throw Failure.missing }
        guard try legacyIDs() == legacy, try reader.snapshot() == s else {throw Failure.rollbackIncomplete}
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        s.selected = ref; s.selectionNonce = UUID(); try publish(&s)
    }
    func remove(_ ref: Ref, vpnInactive: () throws -> Bool = {true}) throws {
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        var s = try writableSnapshot()
        guard !s.hasPendingWrite else { throw Failure.rollbackIncomplete }
        guard s.current.contains(ref) else { throw Failure.missing }
        guard s.retired.count < 64 else { throw Failure.capacity }
        s.current.removeAll{$0 == ref}; s.retired.append(ref)
        if s.selected == ref { s.selected = nil; s.selectionNonce = nil }
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        try publish(&s)
    }
    /// Recovery is safe after interruption at either side of record insertion.
    /// Never deletes any currently published or retired revision.
    func reconcilePendingInsert(vpnInactive: () throws -> Bool = {true}) throws {
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        var s = try writableSnapshot()
        guard let ref = s.pendingInsert else { return }
        guard try vpnInactive(),try reader.snapshot()==s else {throw Failure.rollbackIncomplete}
        _ = try repository.remove(ref)
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        guard try reader.snapshot() == s else {throw Failure.rollbackIncomplete}
        s.pendingInsert = nil; try publish(&s)
    }
    /// Delete only explicitly recorded retired revisions. Retry is idempotent
    /// if a crash happens after item deletion but before catalog publication.
    func reconcileRetired(vpnInactive: () throws -> Bool = {true}) throws {
        guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
        var s = try writableSnapshot()
        guard !s.hasPendingWrite else { throw Failure.rollbackIncomplete }
        for ref in s.retired {
            guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
            guard try reader.snapshot() == s else {throw Failure.rollbackIncomplete}
            _ = try repository.remove(ref)
            guard try vpnInactive() else {throw ProfileBackupError.vpnActive}
            guard try reader.snapshot() == s else {throw Failure.rollbackIncomplete}
            s.retired.removeAll{$0 == ref}; try publish(&s)
        }
    }
}
