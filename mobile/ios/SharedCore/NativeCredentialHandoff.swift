import Foundation

/// Opaque ticket only in control channel and short-lived metadata item.
/// The already-retained immutable revision is the only durable secret record.
/// No production authorization. The receiver recompiles and validates.
struct NativeCredentialHandoff {
    enum Failure: Error { case invalidBinding, expired, unavailable, invalidEnvelope }
    static let maxEnvelopeBytes = 2048
    static let maxCleanupAccounts = 64
    struct Binding: Codable, Equatable {
        let reference: NativeCredentialRecord.Reference
        let session: TransportNativeIdentity
        let selectionNonce: UUID
        var valid: Bool { session.valid && session.provider == reference.kind.providerName }
    }
    enum Purpose:String,Codable {case runtimeReview}
    struct Ticket: Codable, Equatable {
        let id: UUID
        let binding: Binding
        var purpose:Purpose? = nil
        var runtimeOwner:UUID? = nil
        var runtimeProbeIPv4:String? = nil
    }
    private struct Envelope: Codable {
        let version: Int
        let ticket: Ticket
        let issued: Date
        let expires: Date
    }
    let items: NativeCredentialItems
    let repository: NativeCredentialRepository
    let authorizes: (Binding) throws -> Bool
    let now: () -> Date
    init(items: NativeCredentialItems, repository: NativeCredentialRepository, authorizes: @escaping (Binding) throws -> Bool, now: @escaping () -> Date = Date.init) { self.items = items; self.repository = repository; self.authorizes = authorizes; self.now = now }
    private func account(_ id: UUID) -> String { "handoff-v1/\(id.uuidString)" }
    func issue(_ record: NativeCredentialRecord, binding: Binding, runtimeOwner:UUID? = nil,runtimeProbeIPv4:String? = nil) throws -> Ticket {
        guard binding.valid, binding.reference == record.reference, runtimeOwner != nil || runtimeProbeIPv4 == nil, try authorizes(binding) else { throw Failure.invalidBinding }
        guard let stored = try repository.read(record.reference), try stored.encoded() == record.encoded() else { throw Failure.unavailable }
        let issued = now(), ticket = Ticket(id:UUID(),binding:binding,purpose:runtimeOwner == nil ? nil:.runtimeReview,runtimeOwner:runtimeOwner,runtimeProbeIPv4:runtimeProbeIPv4)
        let envelope = Envelope(version:1,ticket:ticket,issued:issued,expires:issued.addingTimeInterval(60))
        let bytes = try JSONEncoder().encode(envelope)
        guard bytes.count <= Self.maxEnvelopeBytes else { throw Failure.invalidEnvelope }
        guard try authorizes(binding) else {throw Failure.invalidBinding}
        try items.insert(account:account(ticket.id),bytes:bytes)
        return ticket
    }
    func redeem(_ ticket: Ticket, expected: Binding, runtimeOwner:UUID? = nil) throws -> NativeCredentialRecord {
        guard expected.valid, ticket.binding == expected,ticket.runtimeOwner==runtimeOwner,(runtimeOwner != nil || ticket.runtimeProbeIPv4==nil),ticket.purpose == (runtimeOwner == nil ? nil:.runtimeReview) else { throw Failure.invalidBinding }
        let name = account(ticket.id)
        guard let raw = try items.read(account:name) else { throw Failure.unavailable }
        // Concurrent readers can read, only one successful delete wins.
        guard try items.remove(account:name) else { throw Failure.unavailable }
        let envelope = try decode(raw, id:ticket.id)
        guard envelope.ticket == ticket else { throw Failure.invalidEnvelope }
        let current = now()
        guard current >= envelope.issued, current < envelope.expires else { throw Failure.expired }
        guard try authorizes(expected), let record = try repository.read(expected.reference), try authorizes(expected) else { throw Failure.unavailable }
        return record
    }
    private func decode(_ raw: Data, id: UUID) throws -> Envelope {
        guard !raw.isEmpty, raw.count <= Self.maxEnvelopeBytes else {throw Failure.invalidEnvelope}
        let value = try JSONDecoder().decode(Envelope.self,from:raw)
        guard value.version == 1, value.ticket.id == id, value.ticket.binding.valid,
              (value.ticket.purpose == nil) == (value.ticket.runtimeOwner == nil),
              value.ticket.runtimeOwner != nil || value.ticket.runtimeProbeIPv4 == nil,
              value.issued.timeIntervalSinceReferenceDate.isFinite,
              value.expires.timeIntervalSinceReferenceDate.isFinite,
              abs(value.expires.timeIntervalSince(value.issued)-60) < 0.001 else {throw Failure.invalidEnvelope}
        return value
    }
    /// Explicit, bounded metadata-only cleanup. Enumeration must come from
    /// the isolated handoff service. UUIDs are never reused. A redeemed or
    /// revoked ticket may disappear concurrently; that is harmless. Unknown
    /// or malformed entries are NOT swept: report them for separate review.
    struct Cleanup: Equatable {
        var removed = 0
        var retained = 0
        var disappeared = 0
        var malformed = 0
    }
    func cleanupExpired(accounts: [String]) throws -> Cleanup {
        guard accounts.count <= Self.maxCleanupAccounts, Set(accounts).count == accounts.count else {throw Failure.invalidEnvelope}
        let ids = try accounts.map { name -> UUID in
            let parts=name.split(separator:"/",omittingEmptySubsequences:false)
            guard parts.count==2,parts[0]=="handoff-v1",let id=UUID(uuidString:String(parts[1])),name==account(id) else {throw Failure.invalidEnvelope}
            return id
        }
        let current=now()
        guard current.timeIntervalSinceReferenceDate.isFinite else {throw Failure.invalidEnvelope}
        var result=Cleanup()
        for id in ids {
            let name=account(id)
            guard let raw=try items.read(account:name) else {result.disappeared+=1;continue}
            guard let envelope=try? decode(raw,id:id) else {result.malformed+=1;continue}
            // If the clock moved backwards, retain rather than infer expiry.
            guard current >= envelope.expires else {result.retained+=1;continue}
            if try items.remove(account:name) {result.removed+=1} else {result.disappeared+=1}
        }
        return result
    }
    @discardableResult func revoke(_ ticket: Ticket) throws -> Bool { try items.remove(account:account(ticket.id)) }
}
