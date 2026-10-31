import Foundation
import CryptoKit
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ManagedProfileContractTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let source = URL(string: "https://api.arvectum.com/v1/managed/manifest")!

    private func manifest(revision: Int = 2, port: Int = 443,
                          host: String = "node.example.com", type: ProxyType = .https) -> ManagedManifestV1 {
        ManagedManifestV1(schemaVersion: 1, issuer: "api.arvectum.com", revision: revision,
                          issuedAt: now.addingTimeInterval(-60), expiresAt: now.addingTimeInterval(3600),
                          profiles: [.init(id: "proxy_01", name: "Managed proxy", host: host, port: port,
                                           type: type, credentialRef: "opaque_ref_01")])
    }
    private func signed(_ item: ManagedManifestV1, key: Curve25519.Signing.PrivateKey,
                        keyID: String = "provider_2026") throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(item)
        return try JSONSerialization.data(withJSONObject: [
            "version": 1, "keyId": keyID,
            "payload": payload.base64EncodedString(),
            "signature": try key.signature(for: payload).base64EncodedString(),
        ], options: [.sortedKeys])
    }
    func testValidSignatureAndPinnedProvider() throws {
        let key = Curve25519.Signing.PrivateKey()
        let manifest = try ManagedProfileContract.verify(signed(manifest(), key: key), from: source,
                                                         keyID: "provider_2026",
                                                         trustedKey: key.publicKey.rawRepresentation, now: now)
        XCTAssertEqual(manifest.profiles.count, 1)
        XCTAssertEqual(manifest.profiles[0].credentialRef, "opaque_ref_01")
    }
    func testWrongKeyAndTamperRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let bytes = try signed(manifest(), key: key)
        XCTAssertThrowsError(try ManagedProfileContract.verify(bytes, from: source, keyID: "provider_2026",
                                                                trustedKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation, now: now))
        var tampered = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        tampered["payload"] = Data("{\"password\":\"leaked\"}".utf8).base64EncodedString()
        let broken = try JSONSerialization.data(withJSONObject: tampered)
        XCTAssertThrowsError(try ManagedProfileContract.verify(broken, from: source, keyID: "provider_2026",
                                                                trustedKey: key.publicKey.rawRepresentation, now: now))
    }
    func testSourceAndExpiredPayloadFailClosed() throws {
        let key = Curve25519.Signing.PrivateKey()
        let bytes = try signed(manifest(), key: key)
        for unsafe in ["http://api.arvectum.com/v1/a", "https://user:pass@api.arvectum.com/x",
                       "https://127.0.0.1/x", "https://api.arvectum.com/x?token=secret"] {
            XCTAssertThrowsError(try ManagedProfileContract.verify(bytes, from: URL(string: unsafe)!,
                                                                    keyID: "provider_2026",
                                                                    trustedKey: key.publicKey.rawRepresentation, now: now))
        }
        XCTAssertThrowsError(try ManagedProfileContract.verify(bytes, from: source,
                                                                keyID: "provider_2026",
                                                                trustedKey: key.publicKey.rawRepresentation,
                                                                now: now.addingTimeInterval(7200)))
    }
    func testInvalidProfilesAndIssuerRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let bad = try signed(manifest(host: "localhost"), key: key)
        XCTAssertThrowsError(try ManagedProfileContract.verify(bad, from: source,
                                                                keyID: "provider_2026",
                                                                trustedKey: key.publicKey.rawRepresentation, now: now))
        let wrongIssuer = URL(string: "https://other.example.com/manifest")!
        XCTAssertThrowsError(try ManagedProfileContract.verify(try signed(manifest(), key: key), from: wrongIssuer,
                                                                keyID: "provider_2026",
                                                                trustedKey: key.publicKey.rawRepresentation, now: now))
    }
    func testIPLiteralIssuerRejectedBeforeTLSRequest() {
        XCTAssertFalse(ManagedProfileContract.validSource(URL(string: "https://127.0.0.1/api")!))
        XCTAssertFalse(ManagedProfileContract.validSource(URL(string: "https://10.10.1.8/api")!))
        XCTAssertFalse(ManagedProfileContract.validSource(URL(string: "https://api.example.local/api")!))
        XCTAssertTrue(ManagedProfileContract.validSource(source))
    }

    func testNoSilentDowngradesOrRevisions() {
        XCTAssertEqual(ManagedProfileContract.refresh(current: nil, next: manifest()), .requiresApproval)
        XCTAssertEqual(ManagedProfileContract.refresh(current: manifest(revision: 2), next: manifest(revision: 2)), .reject)
        XCTAssertEqual(ManagedProfileContract.refresh(current: manifest(revision: 2), next: manifest(revision: 3)), .accept)
        XCTAssertEqual(ManagedProfileContract.refresh(current: manifest(revision: 2), next: manifest(revision: 3, type: .http)), .requiresApproval)
        XCTAssertEqual(ManagedProfileContract.refresh(current: manifest(revision: 2), next: manifest(revision: 3, host: "other.example.com")), .requiresApproval)
    }
}
