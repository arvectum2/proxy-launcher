import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProfileBackupTests: XCTestCase {
    private let testPassphrase = "Sample-Backup-Passphrase"

    private func fixture() -> ProfileBackupPayload {
        let proxy = ProxyProfile(name: "Confidential profile", host: "192.0.2.20", port: 8080,
                                 type: .socks5, username: "user-local")
        return ProfileBackupPayload(profiles: [BackupProfile(profile: proxy, password: "test-credential")],
                                    favorites: [proxy.id], groups: [proxy.id: "Work"])
    }

    func testEncryptedRoundTripPreservesOrganization() throws {
        let source = fixture()
        let data = try ProfileBackupCodec.seal(source, password: testPassphrase)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        for marker in ["192.0.2.20", "user-local", "test-credential", "Confidential profile", "Work"] {
            XCTAssertFalse(encoded.contains(marker))
        }
        XCTAssertEqual(try ProfileBackupCodec.open(data, password: testPassphrase), source)
    }

    func testSaltAndNonceAreRandomForIdenticalProfiles() throws {
        let source = fixture()
        let first = try ProfileBackupCodec.seal(source, password: testPassphrase)
        let second = try ProfileBackupCodec.seal(source, password: testPassphrase)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try ProfileBackupCodec.open(first, password: testPassphrase), source)
        XCTAssertEqual(try ProfileBackupCodec.open(second, password: testPassphrase), source)
    }

    func testUntrustedIterationCountIsRejected() throws {
        let data = try ProfileBackupCodec.seal(fixture(), password: testPassphrase)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["iterations"] = 2_000_000_000
        let invalid = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try ProfileBackupCodec.open(invalid, password: testPassphrase))
    }

    func testWrongPassphraseOrModifiedEnvelopeIsRejected() throws {
        let data = try ProfileBackupCodec.seal(fixture(), password: testPassphrase)
        XCTAssertThrowsError(try ProfileBackupCodec.open(data, password: "Wrong-Backup-Passphrase"))
        var altered = data
        altered[altered.count / 2] ^= 1
        XCTAssertThrowsError(try ProfileBackupCodec.open(altered, password: testPassphrase))
    }

    func testInputBounds() throws {
        XCTAssertThrowsError(try ProfileBackupCodec.seal(fixture(), password: "short"))
        XCTAssertThrowsError(try ProfileBackupCodec.open(Data(repeating: 0, count: 1_048_577), password: testPassphrase))
    }

    func testDuplicateProfileIDsCannotBeExported() throws {
        let proxy = ProxyProfile(name: "Proxy", host: "proxy.invalid", port: 8080, type: .http)
        let payload = ProfileBackupPayload(profiles: [BackupProfile(profile: proxy, password: nil),
                                                     BackupProfile(profile: proxy, password: nil)],
                                           favorites: [], groups: [:])
        XCTAssertThrowsError(try ProfileBackupCodec.seal(payload, password: testPassphrase))
    }
}
