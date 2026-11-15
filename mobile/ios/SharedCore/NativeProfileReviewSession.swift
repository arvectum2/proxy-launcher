import Foundation

/// Metadata-only projection. A row is neither a credential nor proof of a usable transport.
struct NativeProfilePresentation: Equatable {
    enum State: Equatable {case reviewOnly, migrationRequired, recoveryRequired, legacyCollision, unsupportedPolicy}
    struct Row: Equatable, Identifiable {
        let reference:NativeCredentialRecord.Reference
        let number:Int
        var displayName:String? = nil
        var shortID:String {String(reference.profileID.uuidString.prefix(8))}
        let selected:Bool
        let state:State
        var id:UUID {reference.profileID}
        var canReview:Bool {state == .reviewOnly}
        var canConnect:Bool {false}
    }
    let rows:[Row]
    static let empty=Self(rows:[])
    static func read(_ reader:NativeCredentialCatalogReader,legacyIDs:Set<UUID>,hasExclusions:Bool) throws -> Self {
        let snapshot=try reader.snapshot()
        return Self(rows:snapshot.current.enumerated().map { i,ref in
            let state:State
            if snapshot.version != 2 {state = .migrationRequired}
            else if snapshot.hasPendingWrite {state = .recoveryRequired}
            else if legacyIDs.contains(ref.profileID) {state = .legacyCollision}
            else if hasExclusions {state = .unsupportedPolicy}
            else {state = .reviewOnly}
            return Row(reference:ref,number:i+1,displayName:snapshot.displayNames?[ref.profileID.uuidString],selected:snapshot.selected==ref,state:state)
        })
    }
}

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
    private let management:NativePersistentProfileSession
    private let launchBoundary: NativeSessionLaunchBoundary
    init(elapsed: @escaping () -> TimeInterval = {ProcessInfo.processInfo.systemUptime}) {
        let repo=NativeCredentialRepository(items:items)
        repository=repo
        let c=NativeCredentialCatalog(storage:store,repository:repo,legacyIDs:{[]})
        catalog=c;review=NativeRestoreReview(catalog:c,elapsed:elapsed)
        management=NativePersistentProfileSession(catalog:c,policy:{.tunnelOnly},elapsed:elapsed)
        launchBoundary=NativeSessionLaunchBoundary(reader:c.reader,repository:repo,ticketItems:MemoryItems(),legacyIDs:{[]})
    }
    func counts() throws -> Counts {
        let refs=try catalog.reader.snapshot().current
        return Counts(wireGuard:refs.filter{$0.kind == .wireGuard}.count,amneziaWG1:refs.filter{$0.kind == .amneziaWG1}.count,vless:refs.filter{$0.kind == .vlessReality}.count)
    }
    func previewSource(_ source:String,kind:NativeCredentialRecord.Kind) throws -> NativeRestoreReview.Summary {
        management.cancel();return try review.previewSource(source,expected:kind.transport)
    }
    func previewTransfer(_ transfer:NativeImportTransfer)throws->NativeRestoreReview.Summary {management.cancel();return try review.previewTransfer(transfer)}
    func previewAutomatic(_ sources:[String])throws->NativeRestoreReview.Summary {
        management.cancel();return try review.previewAutomatic(sources)
    }
    func prepareRemoval(_ ref:NativeCredentialRecord.Reference)throws->NativePersistentProfileSession.Receipt {
        review.cancel();return try management.prepare(.remove(ref))
    }
    func confirmRemoval(_ receipt:NativePersistentProfileSession.Receipt)throws {
        guard case .remove=receipt.action else{throw NativePersistentProfileSession.Failure.unavailable}
        try management.confirm(receipt,vpnInactive:{true})
        try catalog.reconcileRetired(vpnInactive:{true})
    }
    func previewBackup(_ bytes:Data,password:String) throws -> NativeRestoreReview.Summary {
        management.cancel();return try review.preview(data:bytes,password:password)
    }
    /// True here means the rehearsal has no VPN object at all. Never reuse
    /// this method to approve a real restore or an OS-level inactive check.
    func addToRehearsal(_ summary: NativeRestoreReview.Summary) throws -> Counts {
        _=try review.confirm(summary,vpnInactive:{true})
        return try counts()
    }
    func presentation(legacyIDs:Set<UUID> = [],hasExclusions:Bool = false) throws -> NativeProfilePresentation {
        try NativeProfilePresentation.read(catalog.reader,legacyIDs:legacyIDs,hasExclusions:hasExclusions)
    }
    /// Ephemeral library only: run preflight, never issue a ticket or create an OS session.
    func selectForReview(_ reference:NativeCredentialRecord.Reference,legacyIDs:Set<UUID> = [],hasExclusions:Bool = false) throws -> NativeProfilePresentation {
        cancelReview()
        guard try presentation(legacyIDs:legacyIDs,hasExclusions:hasExclusions).rows.contains(where:{$0.reference==reference && $0.canReview}) else {throw NativeSessionLaunchBoundary.Failure.staleSelection}
        try catalog.select(reference)
        let intent=try launchBoundary.prepare(reference:reference,scope:.syntheticLab,routes:.tunnelOnly,required:[.tcpIPv4],siteExclusions:[],applicationExclusions:[])
        try launchBoundary.finish(intent)
        return try presentation(legacyIDs:legacyIDs,hasExclusions:hasExclusions)
    }
    func encryptedBackup(password:String) throws -> Data {
        try NativeProfileBackupCodec.seal(catalog.reader.currentRecordsForBackup(repository:repository),password:password)
    }
    func cancelReview(){review.cancel();management.cancel()}
    func clear(){cancelReview();store.bytes=nil;items.items.removeAll()}
}

/// Tracks one outstanding asynchronous file-panel action. A callback must
/// carry the receipt captured at presentation, not the latest mutable mode.
/// No reuse of a receipt after cancellation, backgrounding or dismissal.
struct NativeReviewFileLifecycle {
    enum Action: Equatable {case configuration(NativeCredentialRecord.Kind), automaticConfigurations, replacement(NativeCredentialRecord.Reference), backup, export}
    struct Receipt: Equatable {let id: UUID;let action: Action}
    private(set) var pending: Receipt?
    private(set) var visible = false
    mutating func appear(){visible=true}
    mutating func invalidate(){pending=nil}
    mutating func leave(){visible=false;invalidate()}
    mutating func begin(_ action: Action) -> Receipt? {
        guard visible,pending==nil else{return nil}
        let r=Receipt(id:UUID(),action:action);pending=r;return r
    }
    mutating func consume(_ receipt: Receipt?) -> Action? {
        guard visible,let r=receipt,pending==r else{return nil}
        pending=nil;return r.action
    }
}
