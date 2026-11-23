import Foundation
import Darwin

/// Product connection availability is narrower than import and backup.
/// VLESS Reality requires a separately accepted physical TCP underlay.
enum NativeProductTransportGate {
    static func allowsConnection(_ kind:NativeCredentialRecord.Kind)->Bool {
        switch kind {
        case .wireGuard,.amneziaWG1:return true
        case .vlessReality:
#if APL_NATIVE_PRODUCT_RUNTIME && !APL_VLESS_PHYSICAL_QA
            // Production remains fail-closed until exact physical underlay
            // and independent end-to-end VLESS receipt are accepted.
            return false
#else
            return true
#endif
        }
    }
}

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
    func compile(vlessDatagramReview:Bool = false) throws -> (NativeValidationConfiguration, NativeValidationRoute) {
        guard !vlessDatagramReview || reference.kind == .vlessReality else{throw Failure.unsupportedProtocol}
        if reference.kind == .vlessReality {
            let candidate = try VLESSRealityShareLink.parse(source)
            let plan = try NativeVLESSValidationPlan.prepare(candidate)
            let bytes = try XrayVLESSRuntimeConfig.compileValidatedCandidate(candidate,socksPort:39879,datagramReview:vlessDatagramReview)
            return (.init(provider:.rustXray,wireProtocol:.vlessReality,bytes:bytes),.vlessTCP4(plan))
        }
        let config = try NativeWireGuardRuntimeConfig.compile(source,expected:reference.kind.transport)
        let route = try NativeTunnelRoutePlan.prepare(config)
        return (.init(provider:config.provider,wireProtocol:config.wireProtocol,bytes:config.withEngineConfiguration{$0}),.wireGuard(route))
    }
    /// Common full-tunnel candidate for the real-format profile library.
    /// Keeps the engine configuration tied to the same immutable revision
    /// and never reuses the single-destination review route as a default.
    func compileFullTunnelCandidate(admission:NativeRoutingAdmission,
                                    exactDNSAvailable:Bool)throws->NativeFullTunnelCandidate {
        guard admission == .tunnelOnly else{throw NativeTunnelRoutePlan.Failure.unsupportedPolicy}
        guard NativeProductTransportGate.allowsConnection(reference.kind) else{throw NativeTunnelRoutePlan.Failure.unsupportedProtocol}
        guard reference.kind == .amneziaWG1 || exactDNSAvailable else{throw NativeTunnelRoutePlan.Failure.unsupportedPolicy}
        let (configuration,validation)=try compile(vlessDatagramReview:reference.kind == .vlessReality)
        let route:NativeTunnelRoutePlan
        switch validation {
        case .wireGuard(let plan):route=plan
        case .vlessTCP4(let endpoint):route=try NativeTunnelRoutePlan.prepareVLESS(endpoint)
        }
        guard configuration.provider==reference.kind.provider,configuration.wireProtocol==reference.kind.transport,
              route.provider==configuration.provider,validation.remoteAddress==route.remoteAddress,
              validation.remotePort==route.remotePort else{throw Failure.invalidRecord}
        return .init(reference:reference,validation:validation,route:route,configuration:configuration,
                     exactDNSRequired:reference.kind != .amneziaWG1)
    }
    struct Endpoint:Equatable {
        let host:String
        let port:UInt16
        var address:String {host.contains(":") ? "[\(host)]:\(port)":"\(host):\(port)"}
    }
    func endpointForEdit()throws->Endpoint {
        let route=try compile().1
        return Endpoint(host:route.remoteAddress,port:route.remotePort)
    }
    /// Change only the validated endpoint. The source never leaves this type.
    func replacingEndpoint(host:String,port:UInt16)throws->Self {
        guard !host.isEmpty,host.utf8.count<=45,port>0,!host.utf8.contains(0) else{throw Failure.invalidRecord}
        var a4=in_addr(),a6=in6_addr()
        let ipv4=host.withCString{inet_pton(AF_INET,$0,&a4)==1}
        let ipv6=host.withCString{inet_pton(AF_INET6,$0,&a6)==1}
        guard ipv4 || (ipv6 && reference.kind != .vlessReality) else{throw Failure.invalidRecord}
        let endpoint=Endpoint(host:host,port:port),updated:String
        if reference.kind == .vlessReality {
            let old=try VLESSRealityShareLink.parse(source)
            guard var url=URLComponents(string:source.trimmingCharacters(in:.whitespacesAndNewlines)) else{throw Failure.invalidRecord}
            url.host=host;url.port=Int(port)
            guard let next=url.string else{throw Failure.invalidRecord}
            let parsed=try VLESSRealityShareLink.parse(next)
            guard parsed.userID==old.userID,parsed.serverName==old.serverName,parsed.fingerprint==old.fingerprint,parsed.publicKey==old.publicKey,parsed.shortID==old.shortID,parsed.visionFlow==old.visionFlow else{throw Failure.invalidRecord}
            updated=next
        } else {
            let old=try WGQuickConfigurationPreview.validated(source)
            guard old.peerProperties.count==1 else{throw Failure.invalidRecord}
            // Reconstruct from the strict accepted grammar, preserving every value except Endpoint.
            var peer=old.peerProperties[0];peer["endpoint"]=endpoint.address
            func lines(_ fields:[String:String])->[String] {fields.keys.sorted().compactMap{key in fields[key].map{"\(key) = \($0)"}}}
            updated=(["[Interface]"]+lines(old.properties)+["[Peer]"]+lines(peer)).joined(separator:"\n")
            let checked=try WGQuickConfigurationPreview.validated(updated)
            guard checked.properties==old.properties,checked.peerProperties==[peer] else{throw Failure.invalidRecord}
        }
        let result=try Self.create(profileID:reference.profileID,expected:reference.kind.transport,source:updated)
        guard try result.endpointForEdit() != endpointForEdit() else{throw Failure.invalidRecord}
        return result
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


/// Full-route compilation output, not a start envelope. No review probe
/// destination or legacy fallback. Keep secret material redacted.
struct NativeFullTunnelCandidate:CustomStringConvertible,CustomReflectable {
    let reference:NativeCredentialRecord.Reference
    let validation:NativeValidationRoute
    let route:NativeTunnelRoutePlan
    let configuration:NativeValidationConfiguration
    let exactDNSRequired:Bool
    var description:String {"NativeFullTunnelCandidate(redacted)"}
    var customMirror:Mirror {Mirror(self,children:[] as [Mirror.Child])}
}
