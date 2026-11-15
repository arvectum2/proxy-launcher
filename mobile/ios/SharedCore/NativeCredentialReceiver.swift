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
