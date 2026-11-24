import Foundation
import NetworkExtension
#if APL_PRODUCT_OWNER_QA
import CryptoKit
#endif

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var detail = "Отключено"

    // Shared across controller instances in this app process, including Shortcuts.
    private static let operationGate = NativeOperationGate()
    #if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION
    private static var nativeValidationDispatch:NativeValidationDispatch?
    private struct NativeReviewTarget {
        let manager:NETunnelProviderManager
        let connection:NETunnelProviderSession
        let owner:UUID
        let mode:NativeReviewMode
    }
    private enum NativeReviewMode {
        case validation
#if APL_NATIVE_PRODUCT_RUNTIME_REVIEW
        case runtime(probeIPv4:String?,scope:NativeCredentialHandoff.RuntimeScope?,probeIPv6:String?)
#endif
        var name:String {
            switch self {
            case .validation:return "APL Native Credential Validation"
#if APL_NATIVE_PRODUCT_RUNTIME_REVIEW
            case .runtime:return "APL Native Runtime Review"
#endif
            }
        }
        func owns(_ proto:NETunnelProviderProtocol,owner:UUID)->Bool {
            switch self {
            case .validation:return NativeProviderStartRequest.ownsConfiguration(proto.providerConfiguration,owner:owner)
#if APL_NATIVE_PRODUCT_RUNTIME_REVIEW
            case .runtime:return NativeRuntimeReviewRequest.ownsConfiguration(proto.providerConfiguration,owner:owner)
#endif
            }
        }
    }
    private static var nativeValidationTarget:NativeReviewTarget?
    private static var nativeReconcileInFlight=false
    #endif
    private static let configurationName = "Arvectum Proxy Launcher"

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var isConnectedOrConnecting: Bool {
        status == .connected || status == .connecting || status == .reasserting
    }

    var canToggle: Bool {
        status != .disconnecting
    }

    func prepare() async {
        do {
            try await Self.operationGate.perform(.start) {
#if APL_NATIVE_PRODUCT_RUNTIME
                if try await prepareProductManager() {refreshStatus();return}
#endif
                manager = try await loadOrCreateManager()
                refreshStatus()
            }
        } catch {
            detail = ProxyFailureReason.safeDisplay(
                for: userFacingError(error), translate: { AppL10n.tr($0) })
        }
    }

    func connect() async throws {
        try await Self.operationGate.perform(.start) {
            try await connectWithLease()
        }
    }

    /// Inactive native restore adapter. Only read preferences, never create,
    /// reconcile or save managers. This checks visible APL managers, not a
    /// global OS lock; external starts and separate processes remain gated.
    func confirmNativeRestoreForValidation(_ review: NativeRestoreReview,
                                           summary: NativeRestoreReview.Summary) async throws -> [NativeCredentialRecord.Reference] {
        try await Self.operationGate.perform(.restore) {
            defer { review.cancel() }
            let managers = try await loadAllManagers(requireResult:true).filter(isArvectumManager)
            try Task.checkCancellation()
            return try review.confirm(summary,vpnInactive:{
                guard !Task.isCancelled else {return false}
                let known = managers + (self.manager.map { [$0] } ?? [])
                return known.allSatisfy { !$0.isOnDemandEnabled && $0.connection.status == .disconnected }
            })
        }
    }

    #if (DEBUG || APL_NATIVE_PRODUCT_RUNTIME) && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_PERSISTENT_LIBRARY && !targetEnvironment(simulator)
    /// No preference creation or repair. App-process lease, not an OS lock.
    func withNativeLibraryWrite(_ body: (() throws -> Bool) throws -> Void) async throws {
        try await Self.operationGate.perform(.restore) {
            let all=try await loadAllManagers(requireResult:true)
            try Task.checkCancellation()
            let inactive:()throws->Bool = {
                guard !Task.isCancelled else{return false}
                return (all+(self.manager.map{[$0]} ?? [])).allSatisfy{!$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty && $0.connection.status == .disconnected}
            }
            guard try inactive() else{throw ProfileBackupError.vpnActive}
            try body(inactive)
        }
    }
    #endif

    #if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION
    /// Deliberately has no UI caller. Requires an externally provisioned,
    /// uniquely owned validation manager; never creates/saves one here.
    /// Successful API submission is NOT connection or drain acceptance.
    func submitNativeCredentialValidation(reference:NativeCredentialRecord.Reference,owner:UUID) async throws {
        try await submitNativeReview(reference:reference,owner:owner,mode:.validation)
    }
#if APL_NATIVE_PRODUCT_RUNTIME_REVIEW
    /// Explicit supervised review only. Never called by ordinary UI, Settings
    /// or Shortcuts, and never provisions a manager or accepts OS setup as data proof.
    func submitNativeRuntimeReview(reference:NativeCredentialRecord.Reference,owner:UUID,probeIPv4:String?,scope:NativeCredentialHandoff.RuntimeScope?=nil,probeIPv6:String?=nil,stillAuthorized:()->Bool={true}) async throws {
        try await submitNativeReview(reference:reference,owner:owner,mode:.runtime(probeIPv4:probeIPv4,scope:scope,probeIPv6:probeIPv6),stillAuthorized:stillAuthorized)
    }
#endif
    private func reviewOwns(_ item:NETunnelProviderManager,owner:UUID,mode:NativeReviewMode)->Bool {
        guard let proto=item.protocolConfiguration as? NETunnelProviderProtocol else{return false}
        return proto.providerBundleIdentifier==AppShared.providerBundleIdentifier &&
            item.localizedDescription==mode.name && proto.serverAddress==mode.name &&
            mode.owns(proto,owner:owner) && item.isEnabled && !item.isOnDemandEnabled &&
            (item.onDemandRules ?? []).isEmpty && proto.username==nil && proto.passwordReference==nil &&
            proto.identityReference==nil && proto.identityData==nil && proto.identityDataPassword==nil &&
            proto.proxySettings==nil && !proto.includeAllNetworks && !proto.enforceRoutes
    }
    private func reviewManagers(_ all:[NETunnelProviderManager])->[NETunnelProviderManager] {
        all.filter{item in
            let proto=item.protocolConfiguration as? NETunnelProviderProtocol
            let names=["APL Native Credential Validation","APL Native Runtime Review"]
            return NativeProviderStartRequest.hasReservedKey(Array((proto?.providerConfiguration ?? [:]).keys)) ||
                names.contains(item.localizedDescription ?? "") || names.contains(proto?.serverAddress ?? "")
        }
    }
    private func submitNativeReview(reference:NativeCredentialRecord.Reference,owner:UUID,mode:NativeReviewMode,stillAuthorized:()->Bool={true}) async throws {
        guard stillAuthorized(),Self.nativeValidationDispatch==nil,Self.operationGate.active==nil else{throw NativeOperationGate.Failure.busy}
        let store=try ProfileStore(),boundary=store.makeNativeValidationLaunchBoundary()
        guard try store.nativeValidationPolicyIsEmpty() else{throw NativeValidationDispatch.Failure.unownedManager}
        let intent=try boundary.prepare(reference:reference,scope:.syntheticLab,routes:.tunnelOnly,required:[.tcpIPv4],siteExclusions:[],applicationExclusions:[])
        let dispatch=try NativeValidationDispatch(gate:Self.operationGate,boundary:boundary,intent:intent,owner:owner)
        Self.nativeValidationDispatch=dispatch
        do {
            let all=try await loadAllManagers(requireResult:true)
            try Task.checkCancellation()
            let named=reviewManagers(all)
            guard named.count==1,let target=named.first,let connection=target.connection as? NETunnelProviderSession else{throw NativeValidationDispatch.Failure.unownedManager}
            func check()->Bool {
                guard !Task.isCancelled,stillAuthorized(),reviewOwns(target,owner:owner,mode:mode),target.connection === connection,
                    (try? store.nativeValidationPolicyIsEmpty())==true else{return false}
#if APL_NATIVE_RUNTIME_QA_HARNESS
                if case .runtime=mode {
                    guard (try? store.nativeRuntimeQAFixtureIsIsolated(reference))==true,all.filter(isArvectumManager).count==1 else{return false}
                }
#endif
                let visible=all+(self.manager.map{[$0]} ?? [])
                return visible.allSatisfy{!$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty && $0.connection.status == .disconnected}
            }
            Self.nativeValidationTarget=NativeReviewTarget(manager:target,connection:connection,owner:owner,mode:mode)
            switch mode {
            case .validation:
                try dispatch.submit(checkOwnedAndQuiescent:check,start:{try connection.startTunnel(options:$0)})
#if APL_NATIVE_PRODUCT_RUNTIME_REVIEW
            case .runtime(let probeIPv4,let scope,let probeIPv6):
                try dispatch.submitRuntimeReview(probeIPv4:probeIPv4,scope:scope,probeIPv6:probeIPv6,checkOwnedAndQuiescent:check,start:{try connection.startTunnel(options:$0)})
#endif
            }
        } catch {
            if !dispatch.attempted {
                try dispatch.abortBeforeSubmission()
                Self.nativeValidationDispatch=nil;Self.nativeValidationTarget=nil
            }
            // Ambiguous submission retains ownership; never repeat or infer drain.
            throw error
        }
    }
    /// Retry only a failed pre-submit cleanup. Never unlock a submitted start.
    func abortNativeCredentialValidationBeforeSubmission() throws {
        guard let dispatch=Self.nativeValidationDispatch else{return}
        try dispatch.abortBeforeSubmission()
        Self.nativeValidationDispatch=nil;Self.nativeValidationTarget=nil
    }
    private func reviewOwns(_ target:NativeReviewTarget)->Bool {
        target.manager.connection === target.connection && reviewOwns(target.manager,owner:target.owner,mode:target.mode)
    }
    private func reviewCensus(_ all:[NETunnelProviderManager],target:NativeReviewTarget)->Bool {
        let marked=reviewManagers(all)
        guard reviewOwns(target),marked.count==1,let item=marked.first,reviewOwns(item,owner:target.owner,mode:target.mode) else{return false}
        let others=all.filter{$0 !== item}+(manager.flatMap{$0 === target.manager ? nil:[$0]} ?? [])
        return others.allSatisfy{!$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty && $0.connection.status == .disconnected}
    }
    private func reviewExchange(_ request:TransportNativeRequest,target:NativeReviewTarget)async throws->TransportNativeResponse {
        guard !Task.isCancelled,reviewOwns(target),target.connection.status == .connected else{throw NativeValidationDispatch.Failure.unownedManager}
        let bytes=try TransportNativeCodec.encode(request)
        let reply:Data=try await withCheckedThrowingContinuation { continuation in
            let completion=NativeReconcileCompletion(continuation)
            do {try target.connection.sendProviderMessage(bytes){data in
                if let data {completion.finish(.success(data))} else {completion.finish(.failure(NativeValidationDispatch.Failure.invalidState))}
            }}catch{completion.finish(.failure(error))}
            DispatchQueue.global().asyncAfter(deadline:.now()+6){completion.finish(.failure(NativeValidationDispatch.Failure.invalidState))}
        }
        try Task.checkCancellation()
        guard reviewOwns(target),target.connection.status == .connected else{throw NativeValidationDispatch.Failure.unownedManager}
        return try TransportNativeCodec.decode(TransportNativeResponse.self,reply)
    }
#if APL_NATIVE_PRODUCT_RUNTIME_REVIEW
    /// Exact setup receipt only. No peer-ready state, traffic, or retry.
    func observeNativeRuntimeReviewSetup(owner:UUID)async throws->[NativeReviewControlExchange] {
        guard !Self.nativeReconcileInFlight,let dispatch=Self.nativeValidationDispatch,dispatch.attempted,
              let target=Self.nativeValidationTarget,target.owner==owner,case .runtime=target.mode else{throw NativeValidationDispatch.Failure.invalidState}
        Self.nativeReconcileInFlight=true;defer{Self.nativeReconcileInFlight=false}
        let deadline=ProcessInfo.processInfo.systemUptime+8
        while reviewOwns(target) && (target.connection.status == .connecting || target.connection.status == .disconnected) && ProcessInfo.processInfo.systemUptime<deadline {
            try await Task.sleep(nanoseconds:100_000_000)
        }
        let all=try await loadAllManagers(requireResult:true)
        guard !Task.isCancelled,reviewCensus(all,target:target),target.connection.status == .connected else{throw NativeValidationDispatch.Failure.unownedManager}
        let requests=try dispatch.requestSetupObservation()
        var responses:[TransportNativeResponse]=[]
        for request in requests {responses.append(try await reviewExchange(request,target:target))}
        let after=try await loadAllManagers(requireResult:true)
        guard !Task.isCancelled,reviewCensus(after,target:target),target.connection.status == .connected else{throw NativeValidationDispatch.Failure.unownedManager}
        return try dispatch.acceptSetupObservation(responses)
    }
    func reconcileNativeRuntimeReview(owner:UUID)async throws->NativeReviewControlExchange {
        guard let target=Self.nativeValidationTarget,target.owner==owner,case .runtime=target.mode else{throw NativeValidationDispatch.Failure.invalidState}
        return try await reconcileNativeReview()
    }
#endif
    /// Never infer native drain from OS status or from a missing reply.
    func reconcileNativeCredentialValidation() async throws {
        guard let target=Self.nativeValidationTarget,case .validation=target.mode else{throw NativeValidationDispatch.Failure.invalidState}
        _=try await reconcileNativeReview()
    }
    private func reconcileNativeReview()async throws->NativeReviewControlExchange {
        guard !Self.nativeReconcileInFlight,let dispatch=Self.nativeValidationDispatch,dispatch.attempted,
              let target=Self.nativeValidationTarget else{throw NativeValidationDispatch.Failure.invalidState}
        Self.nativeReconcileInFlight=true;defer{Self.nativeReconcileInFlight=false}
        try Task.checkCancellation()
        let before=try await loadAllManagers(requireResult:true)
        guard !Task.isCancelled,reviewCensus(before,target:target) else{throw NativeValidationDispatch.Failure.unownedManager}
        if !dispatch.terminalEvidence {
            let request=try dispatch.requestTerminalDrain()
            try dispatch.acceptTerminalDrain(try await reviewExchange(request,target:target))
        }
        let afterDrain=try await loadAllManagers(requireResult:true)
        guard !Task.isCancelled,reviewCensus(afterDrain,target:target),let exchange=dispatch.terminalExchange else{throw NativeValidationDispatch.Failure.unownedManager}
        if target.connection.status == .connected {target.connection.stopVPNTunnel()}
        let deadline=ProcessInfo.processInfo.systemUptime+10
        while reviewOwns(target) && (target.connection.status == .connected || target.connection.status == .disconnecting) && ProcessInfo.processInfo.systemUptime<deadline {
            try await Task.sleep(nanoseconds:100_000_000)
        }
        try Task.checkCancellation()
        let all=try await loadAllManagers(requireResult:true)
        try dispatch.finishAfterTerminalDrain(osOffAndOwned:{
            guard !Task.isCancelled,reviewCensus(all,target:target),target.connection.status == .disconnected else{return false}
            return all.allSatisfy{!$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty && $0.connection.status == .disconnected}
        })
        Self.nativeValidationDispatch=nil;Self.nativeValidationTarget=nil
        return exchange
    }
    #endif

#if APL_NATIVE_PRODUCT_RUNTIME
    #if APL_PRODUCT_OWNER_QA
    private static let productConfigurationName="APL Native Product Synthetic QA"
    private(set) var qaLaunch:ProfileStore.ProductLaunch?
    #else
    private static let productConfigurationName="APL Native Product"
    #endif
    // Identity must remain distinguishable from iOS's mutable enabled state.
    // A disabled but exactly owner-marked product manager is never legacy.
    private func productManagerMatchesOwner(_ item:NETunnelProviderManager,owner:UUID)->Bool {
        guard let proto=item.protocolConfiguration as? NETunnelProviderProtocol else{return false}
        return proto.providerBundleIdentifier==AppShared.providerBundleIdentifier &&
            item.localizedDescription==Self.productConfigurationName && proto.serverAddress==Self.productConfigurationName &&
            NativeProductStartRequest.ownsConfiguration(proto.providerConfiguration,owner:owner) &&
            !item.isOnDemandEnabled && (item.onDemandRules ?? []).isEmpty &&
            proto.username==nil && proto.passwordReference==nil && proto.identityReference==nil &&
            proto.identityData==nil && proto.identityDataPassword==nil && proto.proxySettings==nil &&
            !proto.includeAllNetworks && !proto.enforceRoutes
    }
    private func ownsProductManager(_ item:NETunnelProviderManager,owner:UUID)->Bool {
        productManagerMatchesOwner(item,owner:owner) && item.isEnabled
    }
    private func splitProductManagers(_ all:[NETunnelProviderManager],owner:UUID?)throws->(legacy:[NETunnelProviderManager],product:NETunnelProviderManager?) {
        let owned=all.filter(isArvectumManager)
        var legacy=[NETunnelProviderManager](),product:NETunnelProviderManager?
        for item in owned {
            if let owner,productManagerMatchesOwner(item,owner:owner) {
                guard product==nil else{throw NativeCredentialReceiver.Failure.invalidIdentity}
                product=item
            } else {
                try requireLegacyManager(item)
                legacy.append(item)
            }
        }
        return (legacy,product)
    }
    /// Legacy must never adopt or mutate a product manager. One exact, inactive
    /// product marker may coexist after native QA or an in-place re-sign.
    /// Any active, on-demand, malformed, or duplicated marker stays blocking.
    private func isDormantProductManager(_ item:NETunnelProviderManager)->Bool {
        guard let proto=item.protocolConfiguration as? NETunnelProviderProtocol else{return false}
        return proto.providerBundleIdentifier==AppShared.providerBundleIdentifier &&
            item.localizedDescription==Self.productConfigurationName &&
            proto.serverAddress==Self.productConfigurationName &&
            (item.connection.status == .disconnected || item.connection.status == .invalid) &&
            !item.isOnDemandEnabled && (item.onDemandRules ?? []).isEmpty &&
            proto.username==nil && proto.passwordReference==nil && proto.identityReference==nil &&
            proto.identityData==nil && proto.identityDataPassword==nil && proto.proxySettings==nil &&
            !proto.includeAllNetworks && !proto.enforceRoutes
    }
    private func legacyManagersExcludingDormantProduct(_ all:[NETunnelProviderManager])throws->[NETunnelProviderManager] {
        var legacy=[NETunnelProviderManager]()
        var dormantCount=0
        for item in all.filter(isArvectumManager) {
            if isDormantProductManager(item) {
                dormantCount+=1
                guard dormantCount==1 else{throw NativeCredentialReceiver.Failure.invalidIdentity}
                continue // Never reload, save, start or remove the native manager.
            }
            try requireLegacyManager(item) // Fail closed on every other reserved manager.
            legacy.append(item)
        }
        return legacy
    }
    #if APL_PRODUCT_OWNER_QA
    // Compare exact configuration metadata only inside the app; no owner data
    // is emitted. Reject unknown/ambiguous manager identities.
    private func qaIdentity(_ item:NETunnelProviderManager)throws->String {
        guard let p=item.protocolConfiguration as? NETunnelProviderProtocol,
            let name=item.localizedDescription,let address=p.serverAddress,
            let bundle=p.providerBundleIdentifier,
            !item.isOnDemandEnabled,(item.onDemandRules ?? []).isEmpty,
            p.username==nil,p.passwordReference==nil,p.identityReference==nil,
            p.identityData==nil,p.identityDataPassword==nil,p.proxySettings==nil else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        let config=p.providerConfiguration ?? [:]
        guard JSONSerialization.isValidJSONObject(config) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        let raw=try JSONSerialization.data(withJSONObject:config,options:.sortedKeys)
        let bytes=Data((name+"|"+address+"|"+bundle+"|"+String(p.includeAllNetworks)+"|"+String(p.enforceRoutes)+"|").utf8)+raw
        return SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    }
    func qaOffCensus()async throws->[String:Bool] {
        let all=try await loadAllManagers(requireResult:true)
        guard all.allSatisfy({$0.connection.status == .disconnected && !$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty}),
              !all.contains(where:isArvectumManager) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        var result=[String:Bool]()
        for item in all {
            let key=try qaIdentity(item)
            guard result[key]==nil else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            result[key]=item.isEnabled
        }
        return result
    }
    func qaStopOwnedManager(owner:UUID)async throws {
        let all=try await loadAllManagers(requireResult:true)
        let owned=all.filter(isArvectumManager)
        guard owned.count<=1,owned.allSatisfy({productManagerMatchesOwner($0,owner:owner)}),
              all.filter({!isArvectumManager($0)}).allSatisfy({$0.connection.status == .disconnected || $0.connection.status == .invalid}) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        if let target=owned.first {
            manager=target;refreshStatus()
            if target.connection.status != .disconnected && target.connection.status != .invalid {
                target.connection.stopVPNTunnel()
                let deadline=Date().addingTimeInterval(10)
                while target.connection.status != .disconnected && target.connection.status != .invalid && Date()<deadline {
                    try await Task.sleep(nanoseconds:100_000_000)
                }
            }
            guard target.connection.status == .disconnected || target.connection.status == .invalid else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        }
    }
    func qaRemoveManager(owner:UUID,baseline:[String:Bool])async throws {
        let all=try await loadAllManagers(requireResult:true)
        let owned=all.filter(isArvectumManager)
        guard owned.count<=1,owned.allSatisfy({productManagerMatchesOwner($0,owner:owner)}),
              all.allSatisfy({($0.connection.status == .disconnected || $0.connection.status == .invalid) && !$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty}) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        for item in owned {try await item.removeFromPreferences()}
        manager=nil;refreshStatus()
        let others=try await loadAllManagers(requireResult:true)
        guard others.count==baseline.count,others.allSatisfy({$0.connection.status == .disconnected || $0.connection.status == .invalid}) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        // iOS can change enabled bits when another manager is activated. Restore
        // only the exact unchanged configuration of a previously enabled APL manager.
        for item in others {
            let key=try qaIdentity(item)
            guard let enabled=baseline[key] else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            if item.isEnabled != enabled {
                guard let p=item.protocolConfiguration as? NETunnelProviderProtocol,
                    p.providerBundleIdentifier==AppShared.providerBundleIdentifier,
                    [Self.configurationName,"APL Native Product"].contains(item.localizedDescription ?? ""),
                    item.localizedDescription==p.serverAddress,
                    !item.isOnDemandEnabled,(item.onDemandRules ?? []).isEmpty else{throw NativeCredentialReceiver.Failure.invalidIdentity}
                item.isEnabled=enabled
                try await save(item);try await reload(item)
            }
        }
        guard try await qaOffCensus()==baseline else{throw NativeCredentialReceiver.Failure.invalidIdentity}
    }
    func qaDrain()async throws->Bool {
        guard let launch=qaLaunch,let session=manager?.connection as? NETunnelProviderSession,
            session.status == .connected else{return false}
        let request=TransportNativeRequest(identity:launch.ticket.binding.session,action:.drain)
        let bytes=try TransportNativeCodec.encode(request)
        let reply:Data?=await withCheckedContinuation { continuation in
            let gate=ProductOwnerQAMessageGate(continuation)
            DispatchQueue.global().asyncAfter(deadline:.now()+8){gate.finish(nil)}
            do{try session.sendProviderMessage(bytes){gate.finish($0)}}catch{gate.finish(nil)}
        }
        guard let reply,let response=try? TransportNativeCodec.decode(TransportNativeResponse.self,reply) else{return false}
        return response.matches(request) && response.state == .drained
    }
    func qaRefresh(){refreshStatus()}
    #endif
    private func prepareProductManager()async throws->Bool {
        let store=try ProfileStore()
        let all=try await loadAllManagers(requireResult:true)
        if try store.nativeProductSelection() == nil {
            _=try legacyManagersExcludingDormantProduct(all)
            return false
        }
        let split=try splitProductManagers(all,owner:store.nativeProductOwner())
        if let product=split.product,product.connection.status != .disconnected {
            manager=product;return true
        }
        if try store.nativeProductSelection() != nil {
            let active=split.legacy.filter{$0.connection.status != .disconnected}
            guard active.count<=1 else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            manager=active.first ?? split.product;return true
        }
        return false
    }

    private func connectProduct(_ store:ProfileStore,selection:NativeProductSelection)async throws {
        var phase = NativeProductStartPhase.managerCensus
        do {
            let all=try await loadAllManagers(requireResult:true)
            let initial=try splitProductManagers(all,owner:store.nativeProductOwner())
            func status(_ item:NETunnelProviderManager)->NativeProductManagerPreflight.Status {
                switch item.connection.status {
                case .disconnected:return .disconnected
                case .invalid:return .invalid
                default:return .activeOrUnknown
                }
            }
            func onDemandOff(_ items:[NETunnelProviderManager])->Bool {
                items.allSatisfy{!$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty}
            }
            func allOff(_ items:[NETunnelProviderManager])->Bool {
                onDemandOff(items) && NativeProductManagerPreflight.permitsLaunch(items.map(status))
            }
            // A signed in-place upgrade may expose an invalid (not connected)
            // *owned product manager* until reloadFromPreferences. Allow exactly
            // that one read-only reconciliation, never a ticket/launch on invalid.
            let ownedIndex=initial.product.flatMap{candidate in
                all.firstIndex(where:{$0 === candidate})
            }
            guard NativeProductTransportGate.allowsConnection(selection.reference.kind),
                  onDemandOff(all),
                  NativeProductManagerPreflight.permitsReadback(all.map(status),ownedProductIndex:ownedIndex),
                  store.nativeRoutingAdmission().permitsSelection,
                  try store.nativeProductSelection()==selection else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            phase = .managerReconcile
            let owner=try store.ensureNativeProductOwner()
            let target:NETunnelProviderManager
            if let prior=initial.product {
                target=prior
                try await reload(target)
                // iOS may disable this app's other VPN configuration after
                // switching to legacy. Only an exact owner-marked, idle,
                // on-demand-free manager may be re-enabled once. No deletion,
                // no cross-manager repair, and no tunnel retry.
                if !target.isEnabled {
                    guard NativeProductManagerPreflight.permitsOwnedReenable(
                        status:status(target), ownerMatches:productManagerMatchesOwner(target,owner:owner),
                        onDemandOff:!target.isOnDemandEnabled && (target.onDemandRules ?? []).isEmpty,
                        isEnabled:target.isEnabled) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
                    target.isEnabled=true
                    try await save(target)
                    try await reload(target)
                }
            } else {
                target=NETunnelProviderManager()
                let proto=NETunnelProviderProtocol()
                proto.providerBundleIdentifier=AppShared.providerBundleIdentifier
                proto.serverAddress=Self.productConfigurationName
                proto.providerConfiguration=NativeProductStartRequest.configuration(owner:owner)
                target.protocolConfiguration=proto
                target.localizedDescription=Self.productConfigurationName
                target.isEnabled=true;target.isOnDemandEnabled=false
                try await save(target);try await reload(target)
            }
            phase = .managerReadback
            let refreshed=try await loadAllManagers(requireResult:true)
            let exact=try splitProductManagers(refreshed,owner:owner)
            guard let readback=exact.product,allOff(refreshed),ownsProductManager(target,owner:owner),
                  ownsProductManager(readback,owner:owner),allOff([target]),
                  let session=target.connection as? NETunnelProviderSession,
                  try store.nativeProductSelection()==selection else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            try Task.checkCancellation()
            phase = .credentialTicket
            let launch=try store.issueNativeProductLaunch(selection,owner:owner)
            #if APL_PRODUCT_OWNER_QA
            qaLaunch=launch
            #endif
            do {
                try Task.checkCancellation()
                guard allOff(refreshed+[target]),ownsProductManager(target,owner:owner),target.connection === session,
                      try store.nativeProductSelection()==selection,store.nativeRoutingAdmission().permitsSelection else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            } catch {try store.revokeNativeProductLaunch(launch);throw error}
            manager=target
            phase = .osSubmission
            // Once submitted, never retry or fall back to legacy. A rejected
            // submission revokes its ticket; a successfully submitted ticket is
            // single-use and expires independently if NE never consumes it.
            try NativeProductStartSubmission.attempt({
                try session.startTunnel(options:launch.options)
            },revoke:{
                try store.revokeNativeProductLaunch(launch)
            })
            TelemetryStore().append(TunnelEvent(type:"native start submitted",
                detail:phase.rawValue))
            refreshStatus()
        } catch {
            // Local metadata only: phase name, never user-owned endpoints
            // nor a raw OS error description.
            TelemetryStore().append(TunnelEvent(type:"native start blocked",
                detail:phase.rawValue))
            throw error
        }
    }
#endif

    private func connectWithLease() async throws {
#if APL_NATIVE_PRODUCT_RUNTIME
        let store=try ProfileStore()
        if let selection=try store.nativeProductSelection(){try await connectProduct(store,selection:selection);return}
#if APL_PRODUCT_OWNER_QA
        throw NativeCredentialReceiver.Failure.invalidIdentity
#endif
#endif
        var manager = try await loadOrCreateManager()
        self.manager = manager

        do {
            try startTunnel(using: manager)
        } catch {
            guard isRepairableConfigurationError(error) else {
                throw userFacingError(error)
            }

            // iOS can keep an existing Network Extension configuration around
            // in a disabled/stale state (for example after reinstalling a
            // development build). Reload, reconcile and persist our complete
            // configuration, then retry once.
            manager = try await loadOrCreateManager(forceSave: true)
            self.manager = manager

            do {
                try startTunnel(using: manager)
            } catch {
                throw userFacingError(error)
            }
        }

        detail = "Подключение…"
        refreshStatus()
    }

    func disconnect() {
        guard Self.operationGate.active != .nativeValidation else{return}
        manager?.connection.stopVPNTunnel()
        detail = "Отключение…"
        refreshStatus()
    }

    /// Explicit Shortcuts disconnection must not report completion before
    /// NetworkExtension has actually left the connected/connecting states.
    func disconnectAndWait() async throws {
        guard isConnectedOrConnecting else { return }
        disconnect()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            try Task.checkCancellation()
            refreshStatus()
            if status == .disconnected || status == .invalid { return }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw NSError(domain: "ArvectumVPN", code: 13,
                      userInfo: [NSLocalizedDescriptionKey: "VPN не успел отключиться. Проверьте состояние подключения."])
    }

    func reconnectIfActive() async throws {
        guard isConnectedOrConnecting else { return }
        disconnect()
        // NetworkExtension shutdown is asynchronous. A fixed sleep can race
        // the previous tunnel and make startVPNTunnel fail intermittently.
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            try Task.checkCancellation()
            let current = manager?.connection.status ?? .invalid
            if current == .disconnected || current == .invalid { break }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        let current = manager?.connection.status ?? .invalid
        guard current == .disconnected || current == .invalid else {
            throw NSError(domain: "ArvectumVPN", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Не удалось дождаться отключения VPN"])
        }
        try await connect()
    }

    /// Restore the previously active tunnel after reverting an exclusion
    /// update. The preceding stop may still be asynchronously disconnecting.
    func restoreAfterFailedExclusionsUpdate() async throws {
        let deadline = Date().addingTimeInterval(8)
        while manager?.connection.status == .disconnecting && Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        guard manager?.connection.status != .disconnecting else {
            throw NSError(domain: "ArvectumVPN", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "VPN ещё отключается; повторите подключение вручную"])
        }
        refreshStatus()
        if isConnectedOrConnecting { try await reconnectIfActive() }
        else { try await connect() }
    }

    private func refreshStatus() {
        status = manager?.connection.status ?? .invalid
        detail = switch status {
        case .invalid, .disconnected: "Отключено"
        case .connecting: "Подключение…"
        case .connected: "Подключено"
        case .reasserting: "Переподключение…"
        case .disconnecting: "Отключение…"
        @unknown default: "Неизвестное состояние"
        }
    }

    private func startTunnel(using manager: NETunnelProviderManager) throws {
        try requireLegacyManager(manager)
        guard let session = manager.connection as? NETunnelProviderSession else {
            throw NSError(
                domain: "ArvectumVPN",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Не удалось открыть VPN-сессию"]
            )
        }
        var tunnelOptions: [String: NSObject] = ["requestedByUser": NSNumber(value: true)]
#if DEBUG
        // An explicit real-device QA run is bounded by two independent kill
        // switches: one in the app, one in the Packet Tunnel extension.
        // This option is never used in App Store distribution binaries.
        if ProcessInfo.processInfo.arguments.contains("-aplEphemeralTunnelQA") {
            let scopedLab = ProcessInfo.processInfo.arguments.contains("-aplSmart3LocalProxyQA") &&
                ProcessInfo.processInfo.arguments.contains("-aplSmart3ScopedDirectLabQA")
            let radioHandoffQA = scopedLab &&
                ProcessInfo.processInfo.arguments.contains("-aplSmart3RadioHandoffQA")
            let qaLimit = radioHandoffQA ? 95 : scopedLab ? 30 : 25
            tunnelOptions["qaStopAfterSeconds"] = NSNumber(value: qaLimit)
            if radioHandoffQA { tunnelOptions["qaRadioHandoff"] = NSNumber(value: true) }
            UserDefaults(suiteName: AppShared.defaultsSuite)?
                .set(qaLimit, forKey: "qaSmart3RadioRequestedDuration.v1")
            if ProcessInfo.processInfo.arguments.contains("-aplSmart3LocalProxyQA") {
                // Disposable physical QA only; no saved credentials/profiles.
                tunnelOptions["qaSmart3ProxyHost"] = "192.168.1.80" as NSString
                tunnelOptions["qaSmart3ProxyPort"] = NSNumber(value: 18081)
                if ProcessInfo.processInfo.arguments.contains("-aplSmart3ScopedDirectLabQA") {
                    tunnelOptions["qaScopedDirect"] = NSNumber(value: true)
                    if ProcessInfo.processInfo.arguments.contains("-aplSmart3PathResetLabQA") {
                        tunnelOptions["qaResetDirectAfterSeconds"] = NSNumber(value: 17)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-aplSmart3TTLResetLabQA") {
                        tunnelOptions["qaDirectTTLSeconds"] = NSNumber(value: 4)
                    }
                }
            }
        }
#endif
        try session.startTunnel(options: tunnelOptions)
    }

    private func loadOrCreateManager(forceSave: Bool = false) async throws -> NETunnelProviderManager {
        let managers = try await loadAllManagers()

#if APL_NATIVE_PRODUCT_RUNTIME
        // A parked native product manager is not an eligible legacy manager.
        // Native starts retain the strict owner-bound census above.
        let matching=try legacyManagersExcludingDormantProduct(managers)
#else
        let matching = managers.filter(isArvectumManager)
        for item in matching {try requireLegacyManager(item)}
#endif
        let manager = matching.first(where: { $0.isEnabled }) ?? matching.first ?? NETunnelProviderManager()

        if !matching.isEmpty {
            try await reload(manager)
        }

        try requireLegacyManager(manager)
        let changed = reconcile(manager)
        if forceSave || changed || matching.isEmpty {
            try await save(manager)
            try await reload(manager)
        }

        return manager
    }

    private func loadAllManagers(requireResult: Bool = false) async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if requireResult && managers == nil {
                    continuation.resume(throwing: ProxyDiagnosticError(.tunnel))
                } else {
                    continuation.resume(returning: managers ?? [])
                }
            }
        }
    }

    private func isArvectumManager(_ manager: NETunnelProviderManager) -> Bool {
#if APL_PRODUCT_OWNER_QA
        return manager.localizedDescription == Self.productConfigurationName ||
            manager.protocolConfiguration?.serverAddress == Self.productConfigurationName
#else
        if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
           proto.providerBundleIdentifier == AppShared.providerBundleIdentifier {
            return true
        }
        return manager.localizedDescription == Self.configurationName
#endif
    }

    /// Do not silently repair or adopt a manager reserved for future native use.
    private func requireLegacyManager(_ manager: NETunnelProviderManager) throws {
        let config=(manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        guard !NativeProviderStartRequest.hasReservedKey(Array(config.keys)),
              !["APL Native Credential Validation","APL Native Runtime Review","APL Native Product"].contains(manager.localizedDescription ?? ""),
              !["APL Native Credential Validation","APL Native Runtime Review","APL Native Product"].contains(manager.protocolConfiguration?.serverAddress ?? "") else {
            throw NSError(domain:"APLNativeStart",code:1)
        }
    }

    @discardableResult
    private func reconcile(_ manager: NETunnelProviderManager) -> Bool {
        var changed = false
        let proto: NETunnelProviderProtocol

        if let existing = manager.protocolConfiguration as? NETunnelProviderProtocol {
            proto = existing
        } else {
            proto = NETunnelProviderProtocol()
            changed = true
        }

        if proto.providerBundleIdentifier != AppShared.providerBundleIdentifier {
            proto.providerBundleIdentifier = AppShared.providerBundleIdentifier
            changed = true
        }

        if proto.serverAddress != Self.configurationName {
            proto.serverAddress = Self.configurationName
            changed = true
        }

        var providerConfiguration = proto.providerConfiguration ?? [:]
        if providerConfiguration["version"] as? String != AppShared.version {
            providerConfiguration["version"] = AppShared.version
            proto.providerConfiguration = providerConfiguration
            changed = true
        }

        if changed {
            // Reassign after creating or mutating the protocol object so
            // NetworkExtension persists the refreshed provider configuration.
            manager.protocolConfiguration = proto
        }

        if manager.localizedDescription != Self.configurationName {
            manager.localizedDescription = Self.configurationName
            changed = true
        }

        if !manager.isEnabled {
            manager.isEnabled = true
            changed = true
        }

        return changed
    }

    private func isRepairableConfigurationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NEVPNErrorDomain else { return false }

        return nsError.code == NEVPNError.Code.configurationDisabled.rawValue
            || nsError.code == NEVPNError.Code.configurationInvalid.rawValue
            || nsError.code == NEVPNError.Code.configurationStale.rawValue
    }

    private func userFacingError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == NEVPNErrorDomain else {
            return ProxyDiagnosticError(ProxyFailureReason.classify(error))
        }
        // Preserve precise, translated guidance while never forwarding a
        // system error description (which could contain private endpoints).
        switch nsError.code {
        case NEVPNError.Code.configurationDisabled.rawValue:
            return ProxyDiagnosticError(.tunnel, recoveryHint: .vpnDisabled)
        case NEVPNError.Code.configurationStale.rawValue:
            return ProxyDiagnosticError(.tunnel, recoveryHint: .vpnStale)
        case NEVPNError.Code.configurationInvalid.rawValue:
            return ProxyDiagnosticError(.tunnel, recoveryHint: .vpnInvalid)
        default:
            return ProxyDiagnosticError(.tunnel)
        }
    }

#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_PRODUCT_RUNTIME_REVIEW && APL_NATIVE_RUNTIME_QA_HARNESS
    /// Separate operator-confirmed manager-only lane. A production/legacy
    /// manager is never edited, adopted, stopped or removed by this method.
    func nativeRuntimeQACanOpenFixtureLibrary()async throws->Bool {
        guard Self.operationGate.active==nil,Self.nativeValidationDispatch==nil else{return false}
        let all=try await loadAllManagers(requireResult:true)
        return try ProfileStore().nativeRuntimeQAFixtureIsIsolated(nil) && all.filter(isArvectumManager).isEmpty && reviewManagers(all).isEmpty &&
            all.allSatisfy{$0.connection.status == .disconnected && !$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty}
    }
    func nativeRuntimeQAFixtureReference()async throws->NativeCredentialRecord.Reference {
        guard try await nativeRuntimeQACanOpenFixtureLibrary() else{throw NativeValidationDispatch.Failure.unownedManager}
        return try ProfileStore().nativeRuntimeQAFixtureReference()
    }
    /// Explicit readback after an interrupted permission prompt. No mutation.
    func readNativeRuntimeQAManager(owner:UUID,reference:NativeCredentialRecord.Reference,authorized:()->Bool)async throws->String {
        guard authorized(),Self.nativeValidationDispatch==nil else{throw NativeValidationDispatch.Failure.invalidState}
        var diagnostic="unavailable"
        try await Self.operationGate.perform(.nativeValidation) {
            let store=try ProfileStore(),all=try await loadAllManagers(requireResult:true)
            let mode=NativeReviewMode.runtime(probeIPv4:nil,scope:nil,probeIPv6:nil)
            let marked=reviewManagers(all)
            let related=all.filter{item in isArvectumManager(item) || marked.contains(where:{$0 === item})}
            guard !Task.isCancelled,authorized(),related.count==1,let item=related.first,
                  reviewOwns(item,owner:owner,mode:mode),
                  all.allSatisfy({$0.connection.status == .disconnected && !$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty}),
                  try store.nativeRuntimeQAFixtureIsIsolated(reference) else{throw NativeValidationDispatch.Failure.unownedManager}
            if #available(iOS 16.0, *) {
                let bytes:Data=try await withCheckedThrowingContinuation { continuation in
                    let completion=NativeReconcileCompletion(continuation)
                    item.connection.fetchLastDisconnectError { error in
                        let result:String
                        if let error=error as NSError? {
                            let known=["NEVPNConnectionErrorDomain","NEVPNErrorDomain","APLNativeRuntimeReview","APLNativeRuntime","APLNativeStart","NSPOSIXErrorDomain"]
                            result=(known.contains(error.domain) ? error.domain:"other")+":"+String(error.code)
                        } else {result="none"}
                        completion.finish(.success(Data(result.utf8)))
                    }
                    DispatchQueue.global().asyncAfter(deadline:.now()+3){completion.finish(.success(Data("unavailable".utf8)))}
                }
                diagnostic=String(decoding:bytes,as:UTF8.self)
            }
            guard authorized(),!Task.isCancelled else{throw NativeValidationDispatch.Failure.invalidState}

        }
        return diagnostic
    }
    func performNativeRuntimeQAManager(owner:UUID,reference:NativeCredentialRecord.Reference,remove:Bool,authorized:()->Bool)async throws {
        guard authorized(),Self.nativeValidationDispatch==nil else{throw NativeValidationDispatch.Failure.invalidState}
        try await Self.operationGate.perform(.nativeValidation) {
            let store=try ProfileStore()
            let mode=NativeReviewMode.runtime(probeIPv4:nil,scope:nil,probeIPv6:nil)
            @MainActor func related(_ all:[NETunnelProviderManager])->[NETunnelProviderManager] {
                let marked=reviewManagers(all)
                return all.filter{item in isArvectumManager(item) || marked.contains(where:{$0 === item})}
            }
            func off(_ all:[NETunnelProviderManager])->Bool {
                all.allSatisfy{$0.connection.status == .disconnected && !$0.isOnDemandEnabled && ($0.onDemandRules ?? []).isEmpty}
            }
            let before=try await loadAllManagers(requireResult:true)
            guard !Task.isCancelled,authorized(),off(before),try store.nativeRuntimeQAFixtureIsIsolated(reference) else{throw NativeValidationDispatch.Failure.unownedManager}
            let known=related(before)
            if remove {
                guard known.count==1,let item=known.first,reviewOwns(item,owner:owner,mode:mode),authorized() else{throw NativeValidationDispatch.Failure.unownedManager}
                try await item.removeFromPreferences()
            } else {
                guard known.isEmpty else{throw NativeValidationDispatch.Failure.unownedManager}
                let item=NETunnelProviderManager(),proto=NETunnelProviderProtocol()
                proto.providerBundleIdentifier=AppShared.providerBundleIdentifier;proto.serverAddress=mode.name
                proto.providerConfiguration=NativeRuntimeReviewRequest.configuration(owner:owner)
                proto.includeAllNetworks=false;proto.enforceRoutes=false;proto.proxySettings=nil
                item.protocolConfiguration=proto;item.localizedDescription=mode.name
                item.isEnabled=true;item.isOnDemandEnabled=false;item.onDemandRules=[]
                guard authorized(),reviewOwns(item,owner:owner,mode:mode) else{throw NativeValidationDispatch.Failure.unownedManager}
                try await item.saveToPreferences()
            }
            // Ambiguous persistence never triggers a blind rollback/retry.
            let after=try await loadAllManagers(requireResult:true),remaining=related(after)
            guard !Task.isCancelled,authorized(),off(after),try store.nativeRuntimeQAFixtureIsIsolated(reference),
                  remaining.count==(remove ? 0:1),remaining.allSatisfy({reviewOwns($0,owner:owner,mode:mode)}) else{throw NativeValidationDispatch.Failure.invalidState}
        }
    }
#endif

    private func save(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func reload(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}

#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION
private final class NativeReconcileCompletion: @unchecked Sendable {
    private let lock=NSLock()
    private var continuation:CheckedContinuation<Data,Error>?
    init(_ continuation:CheckedContinuation<Data,Error>){self.continuation=continuation}
    func finish(_ result:Result<Data,Error>){lock.lock();let c=continuation;continuation=nil;lock.unlock();c?.resume(with:result)}
}
#endif
