import Foundation
import CryptoKit

/// Data-only subscription contract; no fetch, payment, activation or Keychain writes.
enum ManagedManifestError: LocalizedError {
    case unsafeSource, oversized, unsigned, invalid, expired, issuerMismatch
    var errorDescription: String? {
        switch self {
        case .unsafeSource: return "Небезопасный источник подписки"
        case .oversized: return "Слишком большой список профилей"
        case .unsigned: return "Подпись профилей не прошла проверку"
        case .invalid: return "Недопустимый список управляемых профилей"
        case .expired: return "Срок действия списка профилей истёк"
        case .issuerMismatch: return "Поставщик не совпадает с доверенным источником"
        }
    }
}
struct ManagedProxyDescriptor: Codable, Equatable {
    let id: String
    let name: String
    let host: String
    let port: Int
    let type: ProxyType
    let credentialRef: String
}
struct ManagedManifestV1: Codable, Equatable {
    let schemaVersion: Int
    let issuer: String
    let revision: Int
    let issuedAt: Date
    let expiresAt: Date
    let profiles: [ManagedProxyDescriptor]
}
private struct SignedManagedEnvelope: Decodable {
    let version: Int
    let keyId: String
    let payload: String
    let signature: String
}
enum ManagedRefreshDecision: Equatable { case accept, requiresApproval, reject }

enum ManagedProfileContract {
    static let maxPayload = 128 * 1024
    static let maxProfiles = 32
    static let maxLifetime: TimeInterval = 30 * 86400

    static func validDNS(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        // Four decimal octets denote an IP address, not a DNS issuer.
        if parts.count == 4 && parts.allSatisfy({ part in
            guard let value = UInt8(part) else { return false }
            return String(value) == part
        }) { return false }
        return parts.count >= 2 && host.count <= 253 && host == host.lowercased() &&
            !host.hasSuffix(".local") && parts.allSatisfy { label in
                !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
                label.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 }
            }
    }
    static func validSource(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == "https", let host = c.host?.lowercased(),
              validDNS(host), c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, c.port == nil || c.port == 443 else { return false }
        return true
    }
    private static func token(_ value: String, max: Int = 96) -> Bool {
        !value.isEmpty && value.utf8.count <= max && value.utf8.allSatisfy {
            ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) ||
            ($0 >= 48 && $0 <= 57) || $0 == 45 || $0 == 95
        }
    }
    private static func valid(_ p: ManagedProxyDescriptor) -> Bool {
        token(p.id, max: 64) && token(p.credentialRef) && validDNS(p.host) &&
            (1...65535).contains(p.port) && p.type != .auto &&
            !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && p.name.utf8.count <= 80 &&
            !p.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    /// `trustedKey` is selected from a previously approved local key ring;
    /// never fetch a signing key from the same untrusted manifest endpoint.
    static func verify(_ bytes: Data, from source: URL, keyID: String,
                       trustedKey: Data, now: Date = Date()) throws -> ManagedManifestV1 {
        guard validSource(source) else { throw ManagedManifestError.unsafeSource }
        guard bytes.count <= 256 * 1024 else { throw ManagedManifestError.oversized }
        guard let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(json.keys) == Set(["version", "keyId", "payload", "signature"]),
              let envelope = try? JSONDecoder().decode(SignedManagedEnvelope.self, from: bytes),
              envelope.version == 1, envelope.keyId == keyID,
              let payload = Data(base64Encoded: envelope.payload),
              let signature = Data(base64Encoded: envelope.signature),
              payload.count <= maxPayload, signature.count == 64, trustedKey.count == 32 else {
            throw ManagedManifestError.unsigned
        }
        let publicKey: Curve25519.Signing.PublicKey
        do { publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: trustedKey) }
        catch { throw ManagedManifestError.unsigned }
        guard publicKey.isValidSignature(signature, for: payload) else { throw ManagedManifestError.unsigned }
        guard let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              Set(root.keys) == Set(["schemaVersion", "issuer", "revision", "issuedAt", "expiresAt", "profiles"]),
              let items = root["profiles"] as? [[String: Any]],
              !items.isEmpty, items.count <= maxProfiles,
              items.allSatisfy({ Set($0.keys) == Set(["id", "name", "host", "port", "type", "credentialRef"]) }) else {
            throw ManagedManifestError.invalid
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(ManagedManifestV1.self, from: payload),
              manifest.schemaVersion == 1, manifest.revision > 0,
              manifest.issuedAt <= now.addingTimeInterval(300),
              manifest.expiresAt > now, manifest.expiresAt > manifest.issuedAt,
              manifest.expiresAt.timeIntervalSince(manifest.issuedAt) <= maxLifetime else {
            throw ManagedManifestError.expired
        }
        guard manifest.issuer == source.host?.lowercased() else { throw ManagedManifestError.issuerMismatch }
        guard Set(manifest.profiles.map(\.id)).count == manifest.profiles.count,
              manifest.profiles.allSatisfy(valid) else { throw ManagedManifestError.invalid }
        return manifest
    }

    /// Higher revision is insufficient to silently move an existing user to
    /// another endpoint, remove a profile, or downgrade a transport.
    static func refresh(current: ManagedManifestV1?, next: ManagedManifestV1) -> ManagedRefreshDecision {
        guard let current else { return .requiresApproval }
        guard next.issuer == current.issuer, next.revision > current.revision,
              Set(current.profiles.map(\.id)).count == current.profiles.count,
              Set(next.profiles.map(\.id)).count == next.profiles.count else { return .reject }
        let old = Dictionary(uniqueKeysWithValues: current.profiles.map { ($0.id, $0) })
        let updated = Dictionary(uniqueKeysWithValues: next.profiles.map { ($0.id, $0) })
        guard Set(old.keys) == Set(updated.keys) else { return .requiresApproval }
        for (id, profile) in old {
            guard let candidate = updated[id],
                  candidate.host == profile.host,
                  candidate.port == profile.port,
                  candidate.type == profile.type else { return .requiresApproval }
        }
        return .accept
    }
}
