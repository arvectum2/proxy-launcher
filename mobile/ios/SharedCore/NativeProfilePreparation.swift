import Foundation

/// Separate, in-memory preparation boundary. No changes to ProxyProfile,
/// legacy Keychain, backups or manager preferences. A compiled arbitrary
/// profile is NOT an accepted synthetic fixture or a production backend plan.
@MainActor final class NativeProfilePreparation {
    enum Failure: Error, Equatable { case unsupportedProtocol, unknownProfile, staleRevision, wrongProvider, stalePreparation, legacyIDCollision, capacityExceeded }
    struct Revision: Equatable {
        let profileID: UUID
        let revision: UUID
        let wireProtocol: TransportProtocol
        fileprivate init(profileID: UUID, wireProtocol: TransportProtocol) {
            self.profileID = profileID; self.revision = UUID(); self.wireProtocol = wireProtocol
        }
    }
    struct Ticket: Equatable {
        let revision: Revision
        let provider: TransportProvider
        fileprivate let nonce: UUID
    }
    private struct Entry: CustomStringConvertible, CustomReflectable {
        let revision: Revision
        let configuration: NativeWireGuardRuntimeConfig
        var description: String { "NativeProfileEntry(redacted)" }
        var customMirror: Mirror { Mirror(self,children:[:]) }
    }
    private struct Prepared {
        let ticket: Ticket
        let route: NativeTunnelRoutePlan
    }
    private var entries: [UUID: Entry] = [:]
    private var prepared: Prepared?
    private var selected: Revision?
    // Caller-supplied current legacy IDs, checked on every import and consume.
    private let legacyIDs: () throws -> Set<UUID>
    init(legacyIDs: @escaping () throws -> Set<UUID>) { self.legacyIDs = legacyIDs }

    /// Replacement is atomic after validation. Failed edits cannot alter an
    /// existing revision or leave a partially compiled profile behind.
    @discardableResult func stage(profileID: UUID, expected: TransportProtocol, source: String) throws -> Revision {
        guard expected == .wireGuard || expected == .amneziaWG1 else { throw Failure.unsupportedProtocol }
        guard !(try legacyIDs()).contains(profileID) else { throw Failure.legacyIDCollision }
        guard entries[profileID] != nil || entries.count < 32 else { throw Failure.capacityExceeded }
        let config = try NativeWireGuardRuntimeConfig.compile(source,expected:expected)
        _ = try NativeTunnelRoutePlan.prepare(config)
        let revision = Revision(profileID:profileID,wireProtocol:expected)
        entries[profileID] = .init(revision:revision, configuration:config)
        if selected?.profileID == profileID { selected = nil; prepared = nil }
        return revision
    }
    func select(_ revision: Revision) throws {
        _ = try entry(revision)
        selected = revision; prepared = nil
    }
    func remove(profileID: UUID) {
        entries.removeValue(forKey:profileID)
        if selected?.profileID == profileID { selected = nil; prepared = nil }
    }
    func clear() { entries.removeAll(); selected = nil; prepared = nil }
    private func entry(_ revision: Revision) throws -> Entry {
        guard !(try legacyIDs()).contains(revision.profileID) else { throw Failure.legacyIDCollision }
        guard let entry = entries[revision.profileID] else { throw Failure.unknownProfile }
        guard entry.revision == revision else { throw Failure.staleRevision }
        return entry
    }
    /// Only one outstanding preview. Any attempted replacement invalidates
    /// the earlier ticket, including a rejected route/policy preparation.
    func prepare(_ revision: Revision, routes: TransportBackendPlan.RoutePolicy,
                 siteExclusions: [String], applicationExclusions: [String]) throws -> Ticket {
        prepared = nil
        guard selected == revision else { throw Failure.staleRevision }
        let config = try entry(revision).configuration
        let route = try NativeTunnelRoutePlan.prepare(config,routes:routes,siteExclusions:siteExclusions,applicationExclusions:applicationExclusions)
        let ticket = Ticket(revision:revision,provider:config.provider,nonce:UUID())
        prepared = .init(ticket:ticket,route:route)
        return ticket
    }
    /// Validation-only handoff to an offline consumer. Consumes before calling
    /// client code (even on throw). The config is not serialized or exposed as
    /// NE start options. Actual production activation requires a different gate.
    func consumeForValidation<T>(_ ticket: Ticket, provider: TransportProvider,
                                 _ body: (NativeTunnelRoutePlan, Data) throws -> T) throws -> T {
        guard let current = prepared, current.ticket == ticket else { throw Failure.stalePreparation }
        prepared = nil
        guard ticket.provider == provider else { throw Failure.wrongProvider }
        guard selected == ticket.revision else { throw Failure.staleRevision }
        let config = try entry(ticket.revision).configuration
        guard config.provider == provider, current.route.provider == provider else { throw Failure.wrongProvider }
        return try config.withEngineConfiguration { try body(current.route,$0) }
    }
}
