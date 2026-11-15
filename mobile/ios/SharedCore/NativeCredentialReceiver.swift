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
    static let expectedKey="aplNativeExpected"
    static let ticketKey="aplNativeTicket"
    static let validationMode="credential-validation-v1"
    enum Decision {case legacy, denied, validation(NativeProviderStartRequest)}
    let expected:NativeCredentialHandoff.Binding
    let ticketBytes:Data
    var description:String {"NativeProviderStartRequest(redacted)"}
    var customMirror:Mirror {Mirror(self,children:[:])}

    static func hasReservedKey(_ keys:[String])->Bool {keys.contains{$0.lowercased().hasPrefix("aplnative")}}
    static func inspect(configuration:[String:Any]?,options:[String:NSObject]?,validationEnabled:Bool)->Decision {
        let config=configuration ?? [:],opts=options ?? [:]
        guard hasReservedKey(Array(config.keys)) || hasReservedKey(Array(opts.keys)) else{return .legacy}
        guard validationEnabled,Set(config.keys)==[modeKey],config[modeKey] as? String==validationMode,
              Set(opts.keys)==[modeKey,expectedKey,ticketKey],opts[modeKey] as? String==validationMode,
              let raw=opts[expectedKey] as? Data,let ticket=opts[ticketKey] as? Data,
              let expected=try? TransportNativeCodec.decode(NativeCredentialHandoff.Binding.self,raw),expected.valid,
              let decoded=try? TransportNativeCodec.decode(NativeCredentialHandoff.Ticket.self,ticket),decoded.binding==expected else{return .denied}
        return .validation(.init(expected:expected,ticketBytes:ticket))
    }
    /// Validation only, never a success receipt for NE startup.
    func validate(via handoff:NativeCredentialHandoff)throws {
        var receiver=try NativeCredentialReceiver(expected:expected,provider:expected.reference.kind.provider)
        try receiver.consumeForValidation(ticketBytes,via:handoff){_,bytes in
            guard !bytes.isEmpty else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        }
    }
}
