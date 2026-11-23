import Foundation

/// Inactive provider-side boundary. The owner of the start request supplies
/// the expected reference and session independently of the untrusted ticket.
/// Successful validation does not authorize production startup or install routes.
struct NativeCredentialReceiver {
    enum Failure: Error { case invalidIdentity, inactiveRevision, providerMismatch, alreadyConsumed }
    private let expected: NativeCredentialHandoff.Binding
    private let provider: TransportProvider
    private var used = false
    init(expected: NativeCredentialHandoff.Binding, provider: TransportProvider) throws {
        guard expected.valid, expected.reference.kind.provider == provider else { throw Failure.invalidIdentity }
        self.expected = expected; self.provider = provider
    }
    mutating func consumeForValidation<T>(_ bytes: Data, via handoff: NativeCredentialHandoff,
                                          _ validate: (NativeValidationRoute, Data) throws -> T) throws -> T {
        guard !used else { throw Failure.alreadyConsumed }
        used = true  // No retry within the same provider startup attempt.
        let ticket = try TransportNativeCodec.decode(NativeCredentialHandoff.Ticket.self,bytes)
        let record = try handoff.redeem(ticket,expected:expected)
        let (config,route) = try record.compile()
        guard config.provider == provider, route.provider == provider,
              record.reference == expected.reference, config.wireProtocol == expected.reference.kind.transport else { throw Failure.providerMismatch }
        guard try handoff.authorizes(expected) else { throw Failure.inactiveRevision }
        return try config.withEngineConfiguration { try validate(route,$0) }
    }
}

/// Reserved NE start namespace. A native manager restarted by Settings or
/// on-demand without ticket options must never become a legacy proxy tunnel.
struct NativeProviderStartRequest: CustomStringConvertible, CustomReflectable {
    static let modeKey="aplNativeMode"
    static let ownerKey="aplNativeOwner"
    static let expectedKey="aplNativeExpected"
    static let ticketKey="aplNativeTicket"
    static let validationMode="credential-validation-v1"
    enum Decision {case legacy, denied, validation(NativeProviderStartRequest)}
    let owner:UUID
    let expected:NativeCredentialHandoff.Binding
    let ticketBytes:Data
    var description:String {"NativeProviderStartRequest(redacted)"}
    var customMirror:Mirror {Mirror(self,children:[:])}

    static func hasReservedKey(_ keys:[String])->Bool {keys.contains{$0.lowercased().hasPrefix("aplnative")}}
    static func configuration(owner:UUID)->[String:String] {[modeKey:validationMode,ownerKey:owner.uuidString]}
    static func ownsConfiguration(_ configuration:[String:Any]?,owner:UUID)->Bool {
        guard let configuration,Set(configuration.keys)==[modeKey,ownerKey] else{return false}
        return configuration[modeKey] as? String==validationMode && configuration[ownerKey] as? String==owner.uuidString
    }
    static func inspect(configuration:[String:Any]?,options:[String:NSObject]?,validationEnabled:Bool)->Decision {
        let config=configuration ?? [:],opts=options ?? [:]
        guard hasReservedKey(Array(config.keys)) || hasReservedKey(Array(opts.keys)) else{return .legacy}
        guard validationEnabled,let ownerText=config[ownerKey] as? String,let owner=UUID(uuidString:ownerText),ownsConfiguration(config,owner:owner),
              Set(opts.keys)==[modeKey,ownerKey,expectedKey,ticketKey],opts[modeKey] as? String==validationMode,opts[ownerKey] as? String==owner.uuidString,
              let raw=opts[expectedKey] as? Data,let ticket=opts[ticketKey] as? Data,
              let expected=try? TransportNativeCodec.decode(NativeCredentialHandoff.Binding.self,raw),expected.valid,
              let decoded=try? TransportNativeCodec.decode(NativeCredentialHandoff.Ticket.self,ticket),decoded.binding==expected,decoded.validPurpose,decoded.runtimeOwner==nil else{return .denied}
        return .validation(.init(owner:owner,expected:expected,ticketBytes:ticket))
    }
    /// Validation only, never a success receipt for NE startup.
    func validate(via handoff:NativeCredentialHandoff, inspectConfiguration: (NativeValidationRoute,Data)throws->Void = {_,_ in})throws {
        var receiver=try NativeCredentialReceiver(expected:expected,provider:expected.reference.kind.provider)
        try receiver.consumeForValidation(ticketBytes,via:handoff){route,bytes in
            guard !bytes.isEmpty else{throw NativeCredentialReceiver.Failure.invalidIdentity}
            try inspectConfiguration(route,bytes)
        }
    }
}

/// NE status classification used only for an ownership-bound, read-only
/// preference reload before native product start. A stale invalid manager
/// may be re-read; it must become disconnected before a ticket is issued.
enum NativeProductManagerPreflight {
    enum Status: Equatable { case disconnected, invalid, activeOrUnknown }

    static func permitsReadback(_ statuses: [Status], ownedProductIndex: Int?) -> Bool {
        for (index, status) in statuses.enumerated() {
            switch status {
            case .disconnected: continue
            case .invalid:
                guard ownedProductIndex == index else { return false }
            case .activeOrUnknown: return false
            }
        }
        return true
    }

    static func permitsLaunch(_ statuses: [Status]) -> Bool {
        statuses.allSatisfy { $0 == .disconnected }
    }
}

/// Fixed vocabulary for diagnosing a native start without exposing the
/// selected profile, IPs, DNS settings, credentials or raw OS error payload.
enum NativeProductStartPhase: String, CaseIterable {
    case managerCensus = "manager-census"
    case managerReconcile = "manager-reconcile"
    case managerReadback = "manager-readback"
    case credentialTicket = "credential-ticket"
    case osSubmission = "os-submission"
}

/// NE startTunnel may throw synchronously (e.g. stale/disabled config).
/// Its one-use Keychain ticket must then be revoked immediately rather than
/// left pending until expiry. Retain the original NE failure if revocation
/// itself cannot finish; the ticket also has bounded expiry/ownership.
enum NativeProductStartSubmission {
    static func attempt(_ submit: () throws -> Void, revoke: () throws -> Void) throws {
        do { try submit() }
        catch {
            try? revoke()
            throw error
        }
    }
}

/// Production-intent namespace. A distinct one-shot purpose, never a
/// validation/review receipt. No launch permission is implied by decoding.
struct NativeProductStartRequest:CustomStringConvertible,CustomReflectable {
    static let mode="native-product-start-v1"
    let owner:UUID
    let binding:NativeCredentialHandoff.Binding
    private let ticket:NativeCredentialHandoff.Ticket
    var description:String {"NativeProductStartRequest(redacted)"}
    var customMirror:Mirror {Mirror(self,children:[:])}
    static func configuration(owner:UUID)->[String:String] {
        [NativeProviderStartRequest.modeKey:mode,NativeProviderStartRequest.ownerKey:owner.uuidString]
    }
    static func ownsConfiguration(_ configuration:[String:Any]?,owner:UUID)->Bool {
        typealias K=NativeProviderStartRequest
        guard let configuration,Set(configuration.keys)==[K.modeKey,K.ownerKey] else{return false}
        return configuration[K.modeKey] as? String==mode && configuration[K.ownerKey] as? String==owner.uuidString
    }
    static func options(ticket:NativeCredentialHandoff.Ticket,owner:UUID)throws->[String:NSObject] {
        typealias K=NativeProviderStartRequest
        guard ticket.binding.valid,ticket.validPurpose,ticket.purpose == .productStart,
              ticket.runtimeOwner==owner else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        return [K.modeKey:mode as NSString,K.ownerKey:owner.uuidString as NSString,K.expectedKey:try TransportNativeCodec.encode(ticket.binding) as NSData,K.ticketKey:try TransportNativeCodec.encode(ticket) as NSData]
    }
    static func inspect(configuration:[String:Any]?,options:[String:NSObject]?,enabled:Bool)->Self? {
        typealias K=NativeProviderStartRequest
        guard enabled,let configuration,let options,options.count<=32,
              let ownerText=configuration[K.ownerKey] as? String,let owner=UUID(uuidString:ownerText),
              ownsConfiguration(configuration,owner:owner),
              Set(options.keys.filter{K.hasReservedKey([$0])})==[K.modeKey,K.ownerKey,K.expectedKey,K.ticketKey],
              options[K.modeKey] as? String==mode,options[K.ownerKey] as? String==owner.uuidString,
              let raw=options[K.expectedKey] as? Data,let bytes=options[K.ticketKey] as? Data,
              let binding=try? TransportNativeCodec.decode(NativeCredentialHandoff.Binding.self,raw),binding.valid,
              let ticket=try? TransportNativeCodec.decode(NativeCredentialHandoff.Ticket.self,bytes),
              ticket.binding==binding,ticket.validPurpose,ticket.purpose == .productStart,
              ticket.runtimeOwner==owner else{return nil}
        return .init(owner:owner,binding:binding,ticket:ticket)
    }
    func consume(via handoff:NativeCredentialHandoff,admission:()->NativeRoutingAdmission,
                 exactDNSAvailable:Bool)throws->NativeFullTunnelCandidate {
        guard admission() == .tunnelOnly,NativeProductTransportGate.allowsConnection(binding.reference.kind) else{throw NativeTunnelRoutePlan.Failure.unsupportedPolicy}
        let record=try handoff.redeemProductStart(ticket,expected:binding,owner:owner)
        let plan=try record.compileFullTunnelCandidate(admission:admission(),exactDNSAvailable:exactDNSAvailable)
        guard plan.reference==binding.reference,try handoff.authorizes(binding),admission() == .tunnelOnly else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        return plan
    }
}


/// Provider-instance ownership; legacy starts cannot take over native
/// resources and native starts cannot borrow the legacy runner.
final class NativeProductProviderLane: @unchecked Sendable {
    private enum State {case unused,legacy,native}
    private let lock=NSLock()
    private var state=State.unused
    func reserveNative()->Bool {
        lock.lock();defer{lock.unlock()}
        guard state == .unused else{return false};state = .native;return true
    }
    func reserveLegacy()->Bool {
        lock.lock();defer{lock.unlock()}
        guard state != .native else{return false};state = .legacy;return true
    }
    var isNative:Bool {
        lock.lock();defer{lock.unlock()}
        return state == .native
    }
}

/// Explicit native selection, separate from legacy selection and from the
/// catalog's last reviewed profile. Old installations have no product choice.
struct NativeProductSelection:Codable,Equatable {
    let reference:NativeCredentialRecord.Reference
    let nonce:UUID
    static func read(_ bytes:Data?)throws->Self? {
        guard let bytes else{return nil}
        return try TransportNativeCodec.decode(Self.self,bytes)
    }
    static func select(_ reference:NativeCredentialRecord.Reference,
                       catalog:NativeCredentialCatalogReader,legacyIDs:Set<UUID>,
                       admission:NativeRoutingAdmission)throws->Self {
        guard admission == .tunnelOnly else{throw NativeTunnelRoutePlan.Failure.unsupportedPolicy}
        let snapshot=try catalog.snapshot()
        guard snapshot.version==2,!snapshot.hasPendingWrite,snapshot.selected==reference,
              let nonce=snapshot.selectionNonce,
              Set(snapshot.current.map(\.profileID)).isDisjoint(with:legacyIDs) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        return .init(reference:reference,nonce:nonce)
    }
    func authorizes(_ binding:NativeCredentialHandoff.Binding,
                    catalog:NativeCredentialCatalogReader,legacyIDs:Set<UUID>,
                    admission:NativeRoutingAdmission)throws->Bool {
        guard binding.reference==reference,binding.selectionNonce==nonce else{return false}
        return try Self.select(reference,catalog:catalog,legacyIDs:legacyIDs,admission:admission)==self
    }
}
