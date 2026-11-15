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
        static let empty = Self(version:1,current:[],retired:[],selected:nil,pendingInsert:nil)
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
              s.pendingInsert.map({!s.current.contains($0) && !s.retired.contains($0)}) ?? true else { throw Failure.invalidCatalog }
        return s
    }
    func isSelected(_ ref: Ref) throws -> Bool { try snapshot().selected == ref }
    // Explicit call only from authorized export UI in the future. Reads exact
    // current revisions, not retired/pending entries, and rejects changed view.
    func currentRecordsForBackup(repository: NativeCredentialRepository) throws -> [NativeCredentialRecord] {
        let start=try snapshot()
        guard start.pendingInsert == nil else {throw Failure.rollbackIncomplete}
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
        guard original.pendingInsert == nil else { throw Failure.rollbackIncomplete }
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
    func select(_ ref: Ref) throws {
        guard !(try legacyIDs()).contains(ref.profileID) else { throw Failure.collision }
        var s = try reader.snapshot()
        guard s.pendingInsert == nil else { throw Failure.rollbackIncomplete }
        guard s.current.contains(ref), try repository.read(ref) != nil else { throw Failure.missing }
        s.selected = ref; try publish(s)
    }
    func remove(_ ref: Ref) throws {
        var s = try reader.snapshot()
        guard s.pendingInsert == nil else { throw Failure.rollbackIncomplete }
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
        guard s.pendingInsert == nil else { throw Failure.rollbackIncomplete }
        for ref in s.retired {
            _ = try repository.remove(ref)
            s.retired.removeAll{$0 == ref}; try publish(s)
        }
    }
}
