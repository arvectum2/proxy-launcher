import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProxyShareTests: XCTestCase {
    func testPortableQROneProfileRoundTripsAllProtocolTypesAndCredentials() throws {
        for type in ProxyType.allCases {
            let profile = ProxyProfile(name: "Тест 🔑 office", host: "proxy.example.com",
                                       port: 40_321, type: type,
                                       username: "u:%@/space +")
            let password = "p%40@?#:&+ with colon:🔒"
            let url = try ProxyShare.makeDeepLink(profile: profile, password: password)
            XCTAssertEqual(url.scheme, "arvectum-proxy")
            XCTAssertEqual(url.host, "import")
            XCTAssertLessThanOrEqual(url.absoluteString.utf8.count, ProxyShare.maxLinkBytes)
            let payload = try ProxyImport.fromDeepLink(url)
            XCTAssertTrue(payload.hasPrefix(ProxyShare.prefix))
            let imported = try XCTUnwrap(ProxyImport.parse(payload).only)
            XCTAssertEqual(imported.type, type)
            XCTAssertEqual(imported.name, profile.name)
            XCTAssertEqual(imported.host, profile.host)
            XCTAssertEqual(imported.port, profile.port)
            XCTAssertEqual(imported.username, profile.username)
            XCTAssertEqual(imported.password, password)
        }
    }

    func testIPv6AndNoCredentialProfileCanBeShared() throws {
        let profile = ProxyProfile(name: "IPv6", host: "2001:db8::12", port: 1080,
                                   type: .socks5)
        let url = try ProxyShare.makeDeepLink(profile: profile, password: nil)
        let item = try XCTUnwrap(ProxyImport.parse(ProxyImport.fromDeepLink(url)).only)
        XCTAssertEqual(item.type, .socks5)
        XCTAssertEqual(item.host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
                       profile.host)
        XCTAssertEqual(item.port, 1080)
        XCTAssertTrue(item.username.isEmpty)
        XCTAssertTrue(item.password.isEmpty)
    }

    func testDuplicateLinkValuesAndMalformedPayloadFailClosed() throws {
        for invalid in ["apl1.bad!", "apl1.YWJj", "apl1.", "apl1.%40", "apl1.!"] {
            XCTAssertThrowsError(try ProxyImport.parse(invalid))
        }
        let profile = ProxyProfile(name: "A", host: "example.com", port: 8080, type: .auto)
        let url = try ProxyShare.makeDeepLink(profile: profile, password: "secret")
        var components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.queryItems?.append(URLQueryItem(name: "data", value: "apl1.bad"))
        XCTAssertThrowsError(try ProxyImport.fromDeepLink(try XCTUnwrap(components.url)))
    }

    func testOversizedAndInvalidSecretsAreNeverEncoded() {
        let profile = ProxyProfile(name: "A", host: "example.com", port: 8080, type: .auto)
        XCTAssertThrowsError(try ProxyShare.makeDeepLink(
            profile: profile, password: String(repeating: "x", count: 2_000)))
        XCTAssertThrowsError(try ProxyShare.makeDeepLink(
            profile: profile, password: "part\u{0000}secret"))
    }

    func testNewCodecDoesNotChangeLegacyImportOrDuplicateDetection() throws {
        let original = try ProxyImport.parse("socks5://user:pass@example.com:1080")
        XCTAssertEqual(original.count, 1)
        XCTAssertEqual(original[0].type, .socks5)
        XCTAssertEqual(original[0].password, "pass")
        let existing = [ProxyProfile(name: "Same", host: "example.com",
                                     port: 1080, type: .socks5, username: "user")]
        XCTAssertTrue(ProxyImport.withoutDuplicates(original, existing: existing).isEmpty)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
