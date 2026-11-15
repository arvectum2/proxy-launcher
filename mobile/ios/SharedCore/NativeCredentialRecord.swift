import Foundation

/// Immutable versioned record, separate from legacy proxy storage.
struct NativeCredentialRecord: CustomStringConvertible, CustomReflectable {
    enum Kind: String, Codable { case wireGuard, amneziaWG1
        var transport: TransportProtocol { self == .wireGuard ? .wireGuard : .amneziaWG1 }
        var provider: TransportProvider { self == .wireGuard ? .rustXray : .standaloneAWG }
        var providerName: String { self == .wireGuard ? "rust-xray" : "standalone-awg" }
    }
    struct Reference: Codable, Hashable {
        let profileID: UUID
        let revision: UUID
        let kind: Kind
    }
    private struct Payload: Codable {
        let version: Int
        let reference: Reference
        let source: String
    }
    enum Failure: Error { case invalidRecord, unsupportedProtocol, wrongReference }
    let reference: Reference
    private let source: String
    var description: String { "NativeCredentialRecord(redacted)" }
    var customMirror: Mirror { Mirror(self,children:[:]) }
    static let maxBytes = 32_768
    static func create(profileID: UUID, expected: TransportProtocol, source: String) throws -> Self {
        let kind: Kind
        switch expected { case .wireGuard: kind = .wireGuard; case .amneziaWG1: kind = .amneziaWG1; default: throw Failure.unsupportedProtocol }
        let result = Self(reference:.init(profileID:profileID,revision:UUID(),kind:kind),source:source)
        _ = try result.compile(); _ = try result.encoded()
        return result
    }
    func compile() throws -> (NativeWireGuardRuntimeConfig, NativeTunnelRoutePlan) {
        let config = try NativeWireGuardRuntimeConfig.compile(source,expected:reference.kind.transport)
        return (config,try NativeTunnelRoutePlan.prepare(config))
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Payload(version:1,reference:reference,source:source))
        guard !bytes.isEmpty, bytes.count <= Self.maxBytes else { throw Failure.invalidRecord }
        return bytes
    }
    static func decode(_ bytes: Data, expected: Reference) throws -> Self {
        guard !bytes.isEmpty, bytes.count <= maxBytes else { throw Failure.invalidRecord }
        let payload = try JSONDecoder().decode(Payload.self,from:bytes)
        guard payload.version == 1, payload.reference == expected else { throw Failure.wrongReference }
        let result = Self(reference:expected,source:payload.source)
        _ = try result.compile()
        return result
    }
}

/// Add-only and exact deletion. Only successful deletion can consume a ticket.
protocol NativeCredentialItems {
    func insert(account: String, bytes: Data) throws
    func read(account: String) throws -> Data?
    func remove(account: String) throws -> Bool
}

/// Immutable revision storage, not a live profile catalog or migration.
struct NativeCredentialRepository {
    let items: NativeCredentialItems
    private func account(_ ref: NativeCredentialRecord.Reference) -> String {
        "record-v1/\(ref.profileID.uuidString)/\(ref.revision.uuidString)/\(ref.kind.rawValue)"
    }
    func insert(_ record: NativeCredentialRecord) throws {
        try items.insert(account:account(record.reference),bytes:record.encoded())
    }
    func read(_ ref: NativeCredentialRecord.Reference) throws -> NativeCredentialRecord? {
        guard let bytes = try items.read(account:account(ref)) else { return nil }
        return try NativeCredentialRecord.decode(bytes,expected:ref)
    }
    @discardableResult func remove(_ ref: NativeCredentialRecord.Reference) throws -> Bool {
        try items.remove(account:account(ref))
    }
}
