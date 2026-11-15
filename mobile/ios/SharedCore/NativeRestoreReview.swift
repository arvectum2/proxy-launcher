import Foundation

/// App-process coordination only. Holds across suspension; no nested or
/// concurrent operations. External NE/OS starts remain a separate gate.
@MainActor final class NativeOperationGate {
    enum Operation: Equatable { case start, restore }
    enum Failure: Error { case busy }
    private(set) var active: Operation?
    func perform<T>(_ operation: Operation, _ body: () async throws -> T) async throws -> T {
        guard active == nil else {throw Failure.busy}
        active=operation
        defer {active=nil}
        try Task.checkCancellation()
        return try await body()
    }
}

/// A single-use, secret-free display receipt. The decrypted records remain
/// private in memory until confirmation, cancellation or view dismissal.
@MainActor final class NativeRestoreReview {
    struct Summary: Equatable {
        let id: UUID
        let wireGuard: Int
        let amneziaWG1: Int
        let vless: Int
        var count: Int {wireGuard+amneziaWG1+vless}
        let existingCount: Int
    }
    enum Failure: Error {case staleReview, expired}
    private struct Pending {
        let summary: Summary
        let records: [NativeCredentialRecord]
        let snapshot: NativeCredentialCatalogReader.Snapshot
        let legacyIDs: Set<UUID>
        let created: TimeInterval
    }
    private let catalog: NativeCredentialCatalog
    private let elapsed: () -> TimeInterval
    private var pending: Pending?
    init(catalog: NativeCredentialCatalog, elapsed: @escaping () -> TimeInterval = {ProcessInfo.processInfo.systemUptime}) {self.catalog=catalog;self.elapsed=elapsed}
    func cancel() {pending=nil}
    func preview(data: Data,password: String) throws -> Summary {
        pending=nil
        let records=try NativeProfileBackupCodec.open(data,password:password)
        let state=try catalog.reviewState()
        guard !state.0.hasPendingWrite else {throw NativeCredentialCatalog.Failure.rollbackIncomplete}
        guard records.count+state.0.current.count <= NativeProfileBackupCodec.maxProfiles else {throw ProfileBackupError.tooManyProfiles}
        let s=Summary(id:UUID(),wireGuard:records.filter{$0.reference.kind == .wireGuard}.count,amneziaWG1:records.filter{$0.reference.kind == .amneziaWG1}.count,vless:records.filter{$0.reference.kind == .vlessReality}.count,existingCount:state.0.current.count)
        pending=Pending(summary:s,records:records,snapshot:state.0,legacyIDs:state.1,created:elapsed())
        return s
    }
    /// Caller holds app-side lease and supplies an independent live NE guard.
    /// A failed confirmation is consumed; retry requires a new review.
    func confirm(_ review: Summary, vpnInactive: () throws -> Bool) throws -> [NativeCredentialRecord.Reference] {
        guard let p=pending,p.summary==review else {throw Failure.staleReview}
        pending=nil
        let age=elapsed()-p.created
        guard age>=0,age<300 else {throw Failure.expired}
        let state=try catalog.reviewState()
        guard state.0==p.snapshot,state.1==p.legacyIDs else {throw Failure.staleReview}
        return try catalog.restore(p.records,vpnInactive:vpnInactive)
    }
}
