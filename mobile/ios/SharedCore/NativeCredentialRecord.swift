import Foundation
import Darwin

/// Immutable versioned record, separate from legacy proxy storage.
struct NativeCredentialRecord: CustomStringConvertible, CustomReflectable {
    enum Kind: String, Codable { case wireGuard, amneziaWG1, vlessReality
        var transport: TransportProtocol {
            switch self { case .wireGuard:return .wireGuard; case .amneziaWG1:return .amneziaWG1; case .vlessReality:return .vlessReality }
        }
        var provider: TransportProvider { self == .amneziaWG1 ? .standaloneAWG : .rustXray }
        var providerName: String { self == .amneziaWG1 ? "standalone-awg" : "rust-xray" }
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
        var displayName: String? = nil
    }
    enum Failure: Error { case invalidRecord, unsupportedProtocol, wrongReference }
    let reference: Reference
    private let source: String
    private(set) var displayName: String? = nil
    var description: String { "NativeCredentialRecord(redacted)" }
    var customMirror: Mirror { Mirror(self,children:[:]) }
    static let maxBytes = 32_768
    static func normalizedDisplayName(_ raw:String)throws->String? {
        let value=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        guard value.utf8.count<=128,!raw.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0) || CharacterSet.illegalCharacters.contains($0)}) else{throw Failure.invalidRecord}
        return value.isEmpty ? nil:value
    }
    /// Copy for encrypted backup only; never modify the stored revision.
    func withDisplayName(_ name:String?)throws->Self {
        var result=self;result.displayName=try name.flatMap{try Self.normalizedDisplayName($0)};_ = try result.encoded();return result
    }
    static func create(profileID: UUID, expected: TransportProtocol, source: String) throws -> Self {
        guard !source.isEmpty, source.utf8.count <= maxBytes else {throw Failure.invalidRecord}
        let kind: Kind
        switch expected { case .wireGuard: kind = .wireGuard; case .amneziaWG1: kind = .amneziaWG1; case .vlessReality: kind = .vlessReality; default: throw Failure.unsupportedProtocol }
        let result = Self(reference:.init(profileID:profileID,revision:UUID(),kind:kind),source:source)
        _ = try result.compile(); _ = try result.encoded()
        return result
    }
    func compile() throws -> (NativeValidationConfiguration, NativeValidationRoute) {
        if reference.kind == .vlessReality {
            let candidate = try VLESSRealityShareLink.parse(source)
            let plan = try NativeVLESSValidationPlan.prepare(candidate)
            let bytes = try XrayVLESSRuntimeConfig.compileValidatedCandidate(candidate,socksPort:39879)
            return (.init(provider:.rustXray,wireProtocol:.vlessReality,bytes:bytes),.vlessTCP4(plan))
        }
        let config = try NativeWireGuardRuntimeConfig.compile(source,expected:reference.kind.transport)
        let route = try NativeTunnelRoutePlan.prepare(config)
        return (.init(provider:config.provider,wireProtocol:config.wireProtocol,bytes:config.withEngineConfiguration{$0}),.wireGuard(route))
    }
    /// Revalidate and mint new IDs; restore never reuses a session revision.
    func copyForRestore(profileID: UUID) throws -> Self {
        try Self.create(profileID:profileID,expected:reference.kind.transport,source:source).withDisplayName(displayName)
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Payload(version:1,reference:reference,source:source,displayName:displayName))
        guard !bytes.isEmpty, bytes.count <= Self.maxBytes else { throw Failure.invalidRecord }
        return bytes
    }
    static func decode(_ bytes: Data, expected: Reference) throws -> Self {
        guard !bytes.isEmpty, bytes.count <= maxBytes else { throw Failure.invalidRecord }
        let payload = try JSONDecoder().decode(Payload.self,from:bytes)
        guard payload.version == 1, payload.reference == expected else { throw Failure.wrongReference }
        guard try payload.displayName.flatMap({try normalizedDisplayName($0)}) == payload.displayName else{throw Failure.invalidRecord}
        let result = Self(reference:expected,source:payload.source,displayName:payload.displayName)
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

/// Separate validation context, not interchangeable with NE settings.
/// VLESS has TCP4 evidence only: no default routes, DNS or UDP authorization.
struct NativeVLESSValidationPlan: Equatable {
    let remoteAddress: String
    let remotePort: UInt16
    let required: Set<TransportProbeCapability> = [.tcpIPv4]
    static func prepare(_ candidate: VLESSRealityShareLink) throws -> Self {
        var a = in_addr()
        guard candidate.serverHost.withCString({inet_pton(AF_INET,$0,&a)}) == 1 else {throw NativeTunnelRoutePlan.Failure.invalidAddress}
        let n=UInt32(bigEndian:a.s_addr), first=n >> 24
        guard first != 0, first != 127, first < 224, n >> 16 != 0xa9fe else {throw NativeTunnelRoutePlan.Failure.invalidAddress}
        return Self(remoteAddress:candidate.serverHost,remotePort:UInt16(candidate.serverPort))
    }
}

enum NativeValidationRoute: Equatable {
    case wireGuard(NativeTunnelRoutePlan)
    case vlessTCP4(NativeVLESSValidationPlan)
    var provider: TransportProvider {
        switch self {case .wireGuard(let p):return p.provider;case .vlessTCP4:return .rustXray}
    }
    var remoteAddress: String {
        switch self {case .wireGuard(let p):return p.remoteAddress;case .vlessTCP4(let p):return p.remoteAddress}
    }
    var remotePort: UInt16 {
        switch self {case .wireGuard(let p):return p.remotePort;case .vlessTCP4(let p):return p.remotePort}
    }
}

struct NativeValidationConfiguration: CustomStringConvertible, CustomReflectable {
    let provider: TransportProvider
    let wireProtocol: TransportProtocol
    fileprivate let bytes: Data
    var description: String { "NativeValidationConfiguration(redacted)" }
    var customMirror: Mirror { Mirror(self,children:[:]) }
    func withEngineConfiguration<T>(_ body:(Data)throws->T) rethrows -> T {try body(bytes)}
}
