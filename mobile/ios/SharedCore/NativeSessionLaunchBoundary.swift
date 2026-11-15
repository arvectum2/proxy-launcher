import Foundation

/// Integration boundary between the persisted catalog, backend coordinator
/// and provider receiver. No manager creation, network I/O or routing changes.
/// Production requests remain denied by the capability contract.
@MainActor final class NativeSessionLaunchBoundary {
    enum Failure: Error { case busy, staleSelection, wrongSession, invalidIntent }
    struct Intent: Equatable {
        let plan: TransportBackendPlan
        let reference: NativeCredentialRecord.Reference
        let selectionNonce: UUID
        fileprivate let id: UUID

        /// Provider expectation comes from the owned start request, not
        /// from decoding the bearer ticket supplied to the provider.
        func expectedBinding(for session: TransportBackendCoordinator.Session) throws -> NativeCredentialHandoff.Binding {
            guard session.plan == plan, session.token.generation > 0 else {throw Failure.wrongSession}
            return .init(reference:reference,session:.init(epoch:session.token.epoch,generation:session.token.generation,provider:reference.kind.providerName),selectionNonce:selectionNonce)
        }
    }
    struct Launch: CustomStringConvertible, CustomReflectable {
        let ticketBytes: Data
        let expectedBytes: Data
        func validationOptions(owner:UUID)->[String:NSObject] {
            [NativeProviderStartRequest.modeKey:NativeProviderStartRequest.validationMode as NSString,NativeProviderStartRequest.ownerKey:owner.uuidString as NSString,NativeProviderStartRequest.expectedKey:expectedBytes as NSData,NativeProviderStartRequest.ticketKey:ticketBytes as NSData]
        }
        var description: String {"NativeSessionLaunch(redacted)"}
        var customMirror: Mirror {Mirror(self,children:[:])}
    }
    private let reader: NativeCredentialCatalogReader
    private let repository: NativeCredentialRepository
    private let handoff: NativeCredentialHandoff
    private let legacyIDs: () throws -> Set<UUID>
    private var pending: Intent?
    private var issued: (intent:Intent,ticket:NativeCredentialHandoff.Ticket)?

    init(reader:NativeCredentialCatalogReader,repository:NativeCredentialRepository,
         ticketItems:NativeCredentialItems,legacyIDs:@escaping () throws -> Set<UUID>) {
        self.reader=reader;self.repository=repository;self.legacyIDs=legacyIDs
        handoff = .init(items:ticketItems,repository:repository,authorizes:{ binding in
            guard !(try legacyIDs()).contains(binding.reference.profileID) else {return false}
            return try reader.authorizes(binding)
        })
    }

    func prepare(reference:NativeCredentialRecord.Reference,scope:TransportBackendPlan.Scope,
                 routes:TransportBackendPlan.RoutePolicy,required:Set<TransportProbeCapability>,
                 siteExclusions:[String],applicationExclusions:[String]) throws -> Intent {
        guard issued==nil else {throw Failure.busy}
        pending=nil
        let plan=try TransportBackendPlan.prepare(profileID:reference.profileID,revision:reference.revision,protocol:reference.kind.transport,scope:scope,routes:routes,required:required)
        guard siteExclusions.isEmpty,applicationExclusions.isEmpty else {throw NativeTunnelRoutePlan.Failure.unsupportedPolicy}
        guard !(try legacyIDs()).contains(reference.profileID),let nonce=try reader.selectionAuthority(reference),
              let record=try repository.read(reference),try reader.selectionAuthority(reference)==nonce,
              !(try legacyIDs()).contains(reference.profileID) else {throw Failure.staleSelection}
        let (config,route)=try record.compile()
        guard config.provider==plan.provider,route.provider==plan.provider else {throw TransportContractError.providerMismatch}
        guard try reader.selectionAuthority(reference)==nonce else {throw Failure.staleSelection}
        let intent=Intent(plan:plan,reference:reference,selectionNonce:nonce,id:UUID())
        pending=intent;return intent
    }

    /// Call only with the actual coordinator-owned .start session, after
    /// its lease/quiescence checks. Consume the preview even on failure.
    func issue(_ intent:Intent,for session:TransportBackendCoordinator.Session) throws -> Launch {
        try issueOwned(intent,for:session,runtimeOwner:nil,probeIPv4:nil,scope:nil,probeIPv6:nil)
    }
#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_PRODUCT_RUNTIME_REVIEW
    /// Explicit hardware-review caller only, under the existing exclusive
    /// app lease. The ordinary connection screen never invokes this API.
    func issueForRuntimeReview(_ intent:Intent,for session:TransportBackendCoordinator.Session,owner:UUID,probeIPv4:String?,scope:NativeCredentialHandoff.RuntimeScope?=nil,probeIPv6:String?=nil)throws->[String:NSObject] {
#if !APL_NATIVE_EXACT_DNS
        guard scope==nil else{throw Failure.invalidIntent}
#endif
        let binding=try intent.expectedBinding(for:session)
        let draft=NativeCredentialHandoff.Ticket(id:UUID(),binding:binding,purpose:scope==nil ? .runtimeReview:.runtimeDataPlaneReview,runtimeOwner:owner,runtimeProbeIPv4:probeIPv4,runtimeScope:scope,runtimeProbeIPv6:probeIPv6)
        guard NativeRuntimeReviewRequest.validScope(draft) else{throw Failure.invalidIntent}
        let launch=try issueOwned(intent,for:session,runtimeOwner:owner,probeIPv4:probeIPv4,scope:scope,probeIPv6:probeIPv6)
        do{
            let ticket=try TransportNativeCodec.decode(NativeCredentialHandoff.Ticket.self,launch.ticketBytes)
            return try NativeRuntimeReviewRequest.options(ticket:ticket,owner:owner)
        }catch{try finish(intent);throw error}
    }
#endif
    private func issueOwned(_ intent:Intent,for session:TransportBackendCoordinator.Session,runtimeOwner:UUID?,probeIPv4:String?,scope:NativeCredentialHandoff.RuntimeScope?,probeIPv6:String?)throws->Launch {
        guard issued==nil,pending==intent else {throw Failure.invalidIntent}
        pending=nil
        let binding=try intent.expectedBinding(for:session)
        guard !(try legacyIDs()).contains(intent.reference.profileID),try reader.authorizes(binding),
              let record=try repository.read(intent.reference),!(try legacyIDs()).contains(intent.reference.profileID) else {throw Failure.staleSelection}
        let ticket=try handoff.issue(record,binding:binding,runtimeOwner:runtimeOwner,runtimeProbeIPv4:probeIPv4,runtimeScope:scope,runtimeProbeIPv6:probeIPv6)
        // Keep exact cleanup ownership even if encoding or subsequent dispatch fails.
        issued=(intent,ticket)
        do {return Launch(ticketBytes:try TransportNativeCodec.encode(ticket),expectedBytes:try TransportNativeCodec.encode(binding))}
        catch {try finish(intent);throw error}
    }

    /// Never retire a different or already issued ticket on a failed preview.
    func cancelBeforeDispatch(_ intent:Intent)throws {
        if let active=issued {
            guard active.intent==intent else{throw Failure.busy}
            try finish(intent);return
        }
        if pending==intent {pending=nil}
    }

    /// Explicitly retire the exact ticket on dispatch rejection, stop or
    /// confirmed consumption. A failed delete retains ownership for retry.
    func finish(_ intent:Intent) throws {
        if pending==intent {pending=nil;return}
        guard let active=issued,active.intent==intent else {throw Failure.invalidIntent}
        _=try handoff.revoke(active.ticket);issued=nil
    }
}

/// Owns the app process lease across an actual start submission, even if
/// startTunnel throws. Disconnection alone is not proof of native drain.
/// Never manufactures a terminal receipt; exact native drain and a separate
/// OS-off check are required after submission.
@MainActor final class NativeValidationDispatch {
    enum Failure:Error {case invalidState, unownedManager}
    private let gate:NativeOperationGate
    private let lease:UUID
    private let boundary:NativeSessionLaunchBoundary
    private let intent:NativeSessionLaunchBoundary.Intent
    private let owner:UUID
    private var coordinator=TransportBackendCoordinator()
    private var prepared=false
    private var terminalRequest:TransportNativeRequest?
    private(set) var terminalEvidence=false
    private var terminalTicketRetired=false
    private(set) var attempted=false
    private var closed=false
    init(gate:NativeOperationGate,boundary:NativeSessionLaunchBoundary,intent:NativeSessionLaunchBoundary.Intent,owner:UUID)throws {
        self.gate=gate;self.boundary=boundary;self.intent=intent;self.owner=owner
        lease=try gate.reserve(.nativeValidation)
    }
    func submit(checkOwnedAndQuiescent:()->Bool, start:([String:NSObject])throws->Void)throws {
        try submitOwned(checkOwnedAndQuiescent:checkOwnedAndQuiescent,issue:{session in
            try boundary.issue(intent,for:session).validationOptions(owner:owner)
        },start:start)
    }
#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_PRODUCT_RUNTIME_REVIEW
    func submitRuntimeReview(probeIPv4:String?,scope:NativeCredentialHandoff.RuntimeScope?=nil,probeIPv6:String?=nil,checkOwnedAndQuiescent:()->Bool,start:([String:NSObject])throws->Void)throws {
        try submitOwned(checkOwnedAndQuiescent:checkOwnedAndQuiescent,issue:{session in
            try boundary.issueForRuntimeReview(intent,for:session,owner:owner,probeIPv4:probeIPv4,scope:scope,probeIPv6:probeIPv6)
        },start:start)
    }
#endif
    private func submitOwned(checkOwnedAndQuiescent:()->Bool,issue:(TransportBackendCoordinator.Session)throws->[String:NSObject],start:([String:NSObject])throws->Void)throws {
        guard !closed,!attempted,!prepared else{throw Failure.invalidState}
        guard checkOwnedAndQuiescent() else{throw Failure.unownedManager}
        guard case .start(let session)=try coordinator.begin(intent.plan) else{throw Failure.invalidState}
        // Any failure after coordinator admission must be explicitly aborted.
        prepared=true
        let options=try issue(session)
        guard checkOwnedAndQuiescent() else{throw Failure.unownedManager}
        attempted=true
        try start(options)
    }
    /// An independently matched native response plus OS-off state is required.
    /// Neither a disconnected status alone nor a provider error unlocks.
    func requestTerminalDrain()throws -> TransportNativeRequest {
        guard attempted,!closed,!terminalEvidence,let session=coordinator.active else{throw Failure.invalidState}
        let binding=try intent.expectedBinding(for:session)
        let request=TransportNativeRequest(identity:binding.session,action:.drain)
        terminalRequest=request;return request
    }
    func acceptTerminalDrain(_ response:TransportNativeResponse)throws {
        guard attempted,!closed,let request=terminalRequest,response.matches(request),response.state == .drained else{throw Failure.invalidState}
        terminalRequest=nil;terminalEvidence=true
    }
    func finishAfterTerminalDrain(osOffAndOwned:()->Bool)throws {
        guard attempted,!closed,terminalEvidence,osOffAndOwned() else{throw Failure.invalidState}
        if !terminalTicketRetired {try boundary.finish(intent);terminalTicketRetired=true}
        guard osOffAndOwned() else{throw Failure.invalidState}
        closed=true;gate.release(lease)
    }
    /// Only before any invocation of the OS start primitive. If cleanup throws,
    /// retain the process lease and exact dispatch for a later explicit retry.
    func abortBeforeSubmission()throws {
        guard !closed,!attempted else{throw Failure.invalidState}
        try boundary.cancelBeforeDispatch(intent)
        closed=true;gate.release(lease)
    }
}
