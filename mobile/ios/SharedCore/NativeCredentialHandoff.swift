import Foundation

/// Opaque ticket only in control channel and short-lived metadata item.
/// The already-retained immutable revision is the only durable secret record.
/// No production authorization. The receiver recompiles and validates.
struct NativeCredentialHandoff {
    enum Failure: Error { case invalidBinding, expired, unavailable, invalidEnvelope }
    struct Binding: Codable, Equatable {
        let reference: NativeCredentialRecord.Reference
        let session: TransportNativeIdentity
        var valid: Bool { session.valid && session.provider == reference.kind.providerName }
    }
    struct Ticket: Codable, Equatable {
        let id: UUID
        let binding: Binding
    }
    private struct Envelope: Codable {
        let version: Int
        let ticket: Ticket
        let issued: Date
        let expires: Date
    }
    let items: NativeCredentialItems
    let repository: NativeCredentialRepository
    let isSelected: (NativeCredentialRecord.Reference) throws -> Bool
    let now: () -> Date
    init(items: NativeCredentialItems, repository: NativeCredentialRepository, isSelected: @escaping (NativeCredentialRecord.Reference) throws -> Bool, now: @escaping () -> Date = Date.init) { self.items = items; self.repository = repository; self.isSelected = isSelected; self.now = now }
    private func account(_ id: UUID) -> String { "handoff-v1/\(id.uuidString)" }
    func issue(_ record: NativeCredentialRecord, binding: Binding) throws -> Ticket {
        guard binding.valid, binding.reference == record.reference, try isSelected(record.reference) else { throw Failure.invalidBinding }
        guard let stored = try repository.read(record.reference), try stored.encoded() == record.encoded() else { throw Failure.unavailable }
        let issued = now(), ticket = Ticket(id:UUID(),binding:binding)
        let envelope = Envelope(version:1,ticket:ticket,issued:issued,expires:issued.addingTimeInterval(60))
        let bytes = try JSONEncoder().encode(envelope)
        guard bytes.count <= 2048 else { throw Failure.invalidEnvelope }
        try items.insert(account:account(ticket.id),bytes:bytes)
        return ticket
    }
    func redeem(_ ticket: Ticket, expected: Binding) throws -> NativeCredentialRecord {
        guard expected.valid, ticket.binding == expected else { throw Failure.invalidBinding }
        let name = account(ticket.id)
        guard let raw = try items.read(account:name) else { throw Failure.unavailable }
        // Concurrent readers can read, only one successful delete wins.
        guard try items.remove(account:name) else { throw Failure.unavailable }
        guard !raw.isEmpty, raw.count <= 2048 else { throw Failure.invalidEnvelope }
        let envelope = try JSONDecoder().decode(Envelope.self,from:raw)
        guard envelope.version == 1, envelope.ticket == ticket,
              abs(envelope.expires.timeIntervalSince(envelope.issued)-60) < 0.001 else { throw Failure.invalidEnvelope }
        let current = now()
        guard current >= envelope.issued, current < envelope.expires else { throw Failure.expired }
        guard try isSelected(expected.reference), let record = try repository.read(expected.reference), try isSelected(expected.reference) else { throw Failure.unavailable }
        return record
    }
    @discardableResult func revoke(_ ticket: Ticket) throws -> Bool { try items.remove(account:account(ticket.id)) }
}
