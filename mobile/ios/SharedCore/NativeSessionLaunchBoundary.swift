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
        var validationOptions:[String:NSObject] {
            [NativeProviderStartRequest.modeKey:NativeProviderStartRequest.validationMode as NSString,NativeProviderStartRequest.expectedKey:expectedBytes as NSData,NativeProviderStartRequest.ticketKey:ticketBytes as NSData]
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
        guard issued==nil,pending==intent else {throw Failure.invalidIntent}
        pending=nil
        let binding=try intent.expectedBinding(for:session)
        guard !(try legacyIDs()).contains(intent.reference.profileID),try reader.authorizes(binding),
              let record=try repository.read(intent.reference),!(try legacyIDs()).contains(intent.reference.profileID) else {throw Failure.staleSelection}
        let ticket=try handoff.issue(record,binding:binding)
        // Keep exact cleanup ownership even if encoding or subsequent dispatch fails.
        issued=(intent,ticket)
        do {return Launch(ticketBytes:try TransportNativeCodec.encode(ticket),expectedBytes:try TransportNativeCodec.encode(binding))}
        catch {try finish(intent);throw error}
    }

    /// Explicitly retire the exact ticket on dispatch rejection, stop or
    /// confirmed consumption. A failed delete retains ownership for retry.
    func finish(_ intent:Intent) throws {
        if pending==intent {pending=nil;return}
        guard let active=issued,active.intent==intent else {throw Failure.invalidIntent}
        _=try handoff.revoke(active.ticket);issued=nil
    }
}
