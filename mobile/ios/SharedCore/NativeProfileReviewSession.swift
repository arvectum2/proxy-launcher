import Foundation

/// Offline rehearsal of native profile import and encrypted backup UI.
/// Owns only an ephemeral catalog. Does not expose a real Keychain adapter,
/// VPN start authority, configuration bytes or a persistent profile selection.
@MainActor final class NativeProfileReviewSession {
    private final class MemoryCatalog: NativeCredentialCatalogStorage {
        var bytes: Data?
        func load() throws -> Data? {bytes}
        func replace(_ bytes: Data) throws {self.bytes=bytes}
    }
    private final class MemoryItems: NativeCredentialItems {
        var items: [String:Data]=[:]
        func insert(account:String,bytes:Data) throws {
            guard items[account]==nil else {throw NativeCredentialCatalog.Failure.collision}
            items[account]=bytes
        }
        func read(account:String) throws -> Data? {items[account]}
        func remove(account:String) throws -> Bool {items.removeValue(forKey:account) != nil}
    }
    struct Counts: Equatable {
        let wireGuard: Int
        let amneziaWG1: Int
        let vless: Int
        var total:Int {wireGuard+amneziaWG1+vless}
    }
    private let store=MemoryCatalog(), items=MemoryItems()
    private let catalog: NativeCredentialCatalog
    private let repository: NativeCredentialRepository
    private let review: NativeRestoreReview
    init(elapsed: @escaping () -> TimeInterval = {ProcessInfo.processInfo.systemUptime}) {
        let repo=NativeCredentialRepository(items:items)
        repository=repo
        let c=NativeCredentialCatalog(storage:store,repository:repo,legacyIDs:{[]})
        catalog=c;review=NativeRestoreReview(catalog:c,elapsed:elapsed)
    }
    func counts() throws -> Counts {
        let refs=try catalog.reader.snapshot().current
        return Counts(wireGuard:refs.filter{$0.kind == .wireGuard}.count,amneziaWG1:refs.filter{$0.kind == .amneziaWG1}.count,vless:refs.filter{$0.kind == .vlessReality}.count)
    }
    func previewSource(_ source:String,kind:NativeCredentialRecord.Kind) throws -> NativeRestoreReview.Summary {
        try review.previewSource(source,expected:kind.transport)
    }
    func previewBackup(_ bytes:Data,password:String) throws -> NativeRestoreReview.Summary {
        try review.preview(data:bytes,password:password)
    }
    /// True here means the rehearsal has no VPN object at all. Never reuse
    /// this method to approve a real restore or an OS-level inactive check.
    func addToRehearsal(_ summary: NativeRestoreReview.Summary) throws -> Counts {
        _=try review.confirm(summary,vpnInactive:{true})
        return try counts()
    }
    func encryptedBackup(password:String) throws -> Data {
        try NativeProfileBackupCodec.seal(catalog.reader.currentRecordsForBackup(repository:repository),password:password)
    }
    func cancelReview(){review.cancel()}
    func clear(){review.cancel();store.bytes=nil;items.items.removeAll()}
}
