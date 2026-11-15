import Foundation

/// Metadata-only management of the real-format catalog, with explicit
/// snapshot-bound actions. No ticket, engine, OS calls or legacy selection.
@MainActor final class NativePersistentProfileSession {
    enum Action:Equatable {case migrate, recover, purgeRetired, exportBackup, select(NativeCredentialRecord.Reference), remove(NativeCredentialRecord.Reference), rename(NativeCredentialRecord.Reference,String), replace(NativeCredentialRecord.Reference)}
    enum Failure:Error {case stale, unavailable, expired}
    struct State:Equatable {
        let library:NativeProfilePresentation
        let migrationRequired:Bool
        let recoveryRequired:Bool
        let retiredCount:Int
        let selectionNeedsReview:Bool
        let policy:NativeRoutingAdmission
        var policyAllowsSelection:Bool {policy.permitsSelection}
    }
    struct Receipt:Equatable {let id:UUID;let action:Action;let affected:Int;var endpoint:NativeCredentialRecord.Endpoint? = nil}
    private struct Pending {let receipt:Receipt;let snapshot:NativeCredentialCatalogReader.Snapshot;let legacy:Set<UUID>;let time:TimeInterval;let replacement:NativeCredentialRecord?}
    private let catalog:NativeCredentialCatalog
    private let review:NativeRestoreReview
    private let policy:()->NativeRoutingAdmission
    private let elapsed:()->TimeInterval
    struct EndpointEdit:Equatable {let id:UUID;let reference:NativeCredentialRecord.Reference;let endpoint:NativeCredentialRecord.Endpoint}
    private struct EditState {let edit:EndpointEdit;let snapshot:NativeCredentialCatalogReader.Snapshot;let legacy:Set<UUID>;let time:TimeInterval}
    private var editing:EditState?
    private var pending:Pending?
    init(catalog:NativeCredentialCatalog,policy:@escaping()->NativeRoutingAdmission,elapsed:@escaping()->TimeInterval={ProcessInfo.processInfo.systemUptime}) {
        self.catalog=catalog;self.policy=policy;self.elapsed=elapsed
        review=NativeRestoreReview(catalog:catalog,elapsed:elapsed)
    }
    func cancel(){editing=nil;pending=nil;review.cancel()}
    func state()throws->State {
        let (s,ids)=try catalog.reviewState();let admission=policy();let allowed=admission.permitsSelection
        let library=try NativeProfilePresentation.read(catalog.reader,legacyIDs:ids,hasExclusions:!allowed)
        guard try catalog.reader.snapshot()==s else{throw Failure.stale}
        return .init(library:library,migrationRequired:s.version==1,recoveryRequired:s.hasPendingWrite,retiredCount:s.retired.count,selectionNeedsReview:s.selected != nil && s.selectionNonce==nil,policy:admission)
    }
    func previewSource(_ source:String,kind:NativeCredentialRecord.Kind)throws->NativeRestoreReview.Summary {cancel();return try review.previewSource(source,expected:kind.transport)}
    func previewAutomatic(_ sources:[String])throws->NativeRestoreReview.Summary {cancel();return try review.previewAutomatic(sources)}
    func previewTransfer(_ transfer:NativeImportTransfer)throws->NativeRestoreReview.Summary {cancel();return try review.previewTransfer(transfer)}
    func previewBackup(_ bytes:Data,password:String)throws->NativeRestoreReview.Summary {cancel();return try review.preview(data:bytes,password:password)}
    func confirmImport(_ summary:NativeRestoreReview.Summary,vpnInactive:()throws->Bool)throws {
        editing=nil;pending=nil;_ = try review.confirm(summary,vpnInactive:vpnInactive)
    }
    func previewIPRoutes(for ref:NativeCredentialRecord.Reference,explicitRules:[String],explicitIPOptIn:Bool,vpnInactive:()throws->Bool)throws->NativeIPSplitRoutePlan {
        cancel()
        guard explicitIPOptIn,policy() == .tunnelOnly else{throw Failure.unavailable}
        // Reject invalid input before a credential read.
        guard (1...64).contains(explicitRules.count) else{throw NativeIPSplitRoutePlan.Failure.invalidCount}
        _ = try explicitRules.map(NativeLiteralIPPrefix.init)
        let (snapshot,legacy)=try catalog.reviewState()
        let base=try catalog.selectedRouteForReview(ref,expected:snapshot,expectedLegacy:legacy,vpnInactive:vpnInactive)
        let plan=try NativeIPSplitRoutePlan.prepare(base:base,explicitRules:explicitRules,existingPolicy:policy(),explicitIPOptIn:explicitIPOptIn)
        guard try vpnInactive(),try catalog.reader.snapshot()==snapshot,policy() == .tunnelOnly else{throw Failure.stale}
        return plan
    }
    func beginEndpointEdit(_ ref:NativeCredentialRecord.Reference,vpnInactive:()throws->Bool)throws->EndpointEdit {
        cancel();let (s,legacy)=try catalog.reviewState()
        let record=try catalog.recordForEndpointEdit(ref,expected:s,expectedLegacy:legacy,vpnInactive:vpnInactive)
        let edit=EndpointEdit(id:UUID(),reference:ref,endpoint:try record.endpointForEdit())
        let now=elapsed();guard now.isFinite,now>=0 else{throw Failure.expired}
        editing=EditState(edit:edit,snapshot:s,legacy:legacy,time:now);return edit
    }
    func previewEndpointEdit(_ edit:EndpointEdit,host:String,port:UInt16,vpnInactive:()throws->Bool)throws->Receipt {
        guard let state=editing,state.edit==edit else{throw Failure.stale}
        cancel();let age=elapsed()-state.time;guard age.isFinite,age>=0,age<300 else{throw Failure.expired}
        let old=try catalog.recordForEndpointEdit(edit.reference,expected:state.snapshot,expectedLegacy:state.legacy,vpnInactive:vpnInactive)
        let record=try old.replacingEndpoint(host:host,port:port)
        let endpoint=try record.endpointForEdit()
        guard try vpnInactive(),try catalog.reader.snapshot()==state.snapshot else{throw Failure.stale}
        return try prepareAction(.replace(edit.reference),replacement:record,endpoint:endpoint,expected:state.snapshot,expectedLegacy:state.legacy)
    }
    func previewReplacement(_ source:String,for ref:NativeCredentialRecord.Reference)throws->Receipt {
        cancel()
        let record=try NativeCredentialRecord.create(profileID:ref.profileID,expected:ref.kind.transport,source:source)
        return try prepareAction(.replace(ref),replacement:record)
    }
    func prepare(_ action:Action)throws->Receipt {try prepareAction(action,replacement:nil)}
    private func prepareAction(_ action:Action,replacement:NativeCredentialRecord?,endpoint:NativeCredentialRecord.Endpoint?=nil,expected:NativeCredentialCatalogReader.Snapshot?=nil,expectedLegacy:Set<UUID>?=nil)throws->Receipt {
        cancel();let (s,legacy)=try catalog.reviewState();let count:Int
        guard expected.map({$0==s}) ?? true,expectedLegacy.map({$0==legacy}) ?? true else{throw Failure.stale}
        switch action {
        case .migrate:guard s.version==1 else{throw Failure.unavailable};count=s.current.count
        case .recover:guard s.version==2,s.hasPendingWrite else{throw Failure.unavailable};count=s.pendingRestore?.count ?? 1
        case .exportBackup:guard s.version==2,!s.hasPendingWrite,!s.current.isEmpty,Set(s.current.map(\.profileID)).isDisjoint(with:legacy) else{throw Failure.unavailable};count=s.current.count
        case .purgeRetired:guard s.version==2,!s.hasPendingWrite,!s.retired.isEmpty else{throw Failure.unavailable};count=s.retired.count
        case .select(let ref):guard s.version==2,!s.hasPendingWrite,s.current.contains(ref),!legacy.contains(ref.profileID),policy().permitsSelection else{throw Failure.unavailable};count=1
        case .rename(let ref,let name):guard s.version==2,!s.hasPendingWrite,s.current.contains(ref),!legacy.contains(ref.profileID) else{throw Failure.unavailable};_ = try NativeCredentialRecord.normalizedDisplayName(name);count=1
        case .replace(let ref):guard let replacement,replacement.reference.profileID==ref.profileID,replacement.reference.kind==ref.kind,s.version==2,!s.hasPendingWrite,s.current.contains(ref),!legacy.contains(ref.profileID),s.retired.count<64 else{throw Failure.unavailable};count=1
        case .remove(let ref):guard s.version==2,!s.hasPendingWrite,s.current.contains(ref) else{throw Failure.unavailable};count=1
        }
        let now=elapsed();guard now.isFinite,now>=0 else{throw Failure.expired}
        let receipt=Receipt(id:UUID(),action:action,affected:count,endpoint:endpoint)
        pending=Pending(receipt:receipt,snapshot:s,legacy:legacy,time:now,replacement:replacement);return receipt
    }
    private func consume(_ receipt:Receipt)throws->Pending {
        guard let p=pending,p.receipt==receipt else{throw Failure.stale}
        pending=nil;let age=elapsed()-p.time;guard age.isFinite,age>=0,age<300 else{throw Failure.expired}
        let (s,legacy)=try catalog.reviewState();guard s==p.snapshot,legacy==p.legacy else{throw Failure.stale}
        return p
    }
    func confirmExport(_ receipt:Receipt,password:String,vpnInactive:()throws->Bool)throws->Data {
        let p=try consume(receipt);guard receipt.action == .exportBackup else{throw Failure.unavailable}
        return try catalog.encryptedBackup(password:password,expected:p.snapshot,expectedLegacy:p.legacy,vpnInactive:vpnInactive)
    }
    func confirm(_ receipt:Receipt,vpnInactive:()throws->Bool)throws {
        let p=try consume(receipt);let s=p.snapshot
        guard try vpnInactive() else{throw ProfileBackupError.vpnActive}
        switch receipt.action {
        case .exportBackup:throw Failure.unavailable
        case .migrate:try catalog.migrateLegacyForValidation(vpnInactive:vpnInactive)
        case .recover:
            if s.pendingInsert != nil {try catalog.reconcilePendingInsert(vpnInactive:vpnInactive)}
            else {try catalog.reconcilePendingRestore(vpnInactive:vpnInactive)}
        case .purgeRetired:try catalog.reconcileRetired(vpnInactive:vpnInactive)
        case .select(let ref):
            try catalog.select(ref,vpnInactive:{try vpnInactive() && self.policy().permitsSelection})
        case .rename(let ref,let name):try catalog.rename(ref,name:name,vpnInactive:vpnInactive)
        case .replace(let ref):
            guard let record=p.replacement else{throw Failure.unavailable}
            try catalog.replace(ref,with:record,expected:s,expectedLegacy:p.legacy,vpnInactive:vpnInactive)
        case .remove(let ref):try catalog.remove(ref,vpnInactive:vpnInactive)
        }
    }
}
