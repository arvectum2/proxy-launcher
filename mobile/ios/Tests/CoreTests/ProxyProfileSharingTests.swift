import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProxyProfileSharingTests: XCTestCase {
    func testHTTPShareQRAndExistingImportRoundTrip() throws {
        let profile = ProxyProfile(name: "Fast proxy", host: "proxy.example.com",
                                   port: 8080, type: .http, username: "john")
        let url = try ProxyProfileSharing.deepLink(profile: profile, password: "sec ret:%#?@")
        XCTAssertEqual(url.scheme, "arvectum-proxy")
        XCTAssertEqual(url.host, "import")
        let scanned = try ProxyProfileSharing.scannedSource(url.absoluteString)
        let imported = try XCTUnwrap(ProxyImport.parse(scanned).first)
        XCTAssertEqual(imported.name, profile.name)
        XCTAssertEqual(imported.host, profile.host)
        XCTAssertEqual(imported.port, profile.port)
        XCTAssertEqual(imported.type, profile.type)
        XCTAssertEqual(imported.username, "john")
        XCTAssertEqual(imported.password, "sec ret:%#?@")
    }

    func testSOCKS5IPv6AndUnicodeNameRoundTrip() throws {
        let profile = ProxyProfile(name: "Быстрый прокси 🚀", host: "2001:db8::3",
                                   port: 1080, type: .socks5, username: "user:name")
        let link = try ProxyProfileSharing.deepLink(profile: profile, password: "пароль/γ@")
        let parsed = try XCTUnwrap(ProxyImport.parse(ProxyProfileSharing.scannedSource(
            link.absoluteString)).first)
        XCTAssertEqual(parsed.name, profile.name)
        XCTAssertEqual(parsed.host, "[2001:db8::3]")
        XCTAssertEqual(parsed.username, "user:name")
        XCTAssertEqual(parsed.password, "пароль/γ@")
    }

    func testHTTPSWithoutCredentialsAndLegacyQRStillWork() throws {
        let profile = ProxyProfile(name: "Public", host: "example.org",
                                   port: 443, type: .https)
        let link = try ProxyProfileSharing.deepLink(profile: profile, password: nil)
        let imported = try ProxyImport.parse(ProxyProfileSharing.scannedSource(link.absoluteString))
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].type, .https)
        XCTAssertEqual(imported[0].username, "")
        XCTAssertEqual(imported[0].password, "")
        XCTAssertEqual(try ProxyImport.parse(
            ProxyProfileSharing.scannedSource("socks5://user:pwd@proxy.example.com:1080")).count, 1)
    }

    func testRejectsAutoAndUntrustedDeeplinkQR() throws {
        let automatic = ProxyProfile(name: "automatic", host: "example.org",
                                     port: 8080, type: .auto)
        XCTAssertThrowsError(try ProxyProfileSharing.deepLink(profile: automatic, password: "x"))
        for malicious in [
            "arvectum-proxy://other?data=http%3A%2F%2Fproxy.example.com%3A80",
            "arvectum-proxy://import?data=garbage",
            "arvectum-proxy://import?data=http%3A%2F%2Fexample.com%3A80&data=other",
        ] {
            XCTAssertThrowsError(try ProxyProfileSharing.scannedSource(malicious))
        }
    }

    func testNoWriteToSourceStoreOnShare() throws {
        let profile = ProxyProfile(name: "Direct only", host: "proxy.example",
                                   port: 80, type: .http)
        let one = try ProxyProfileSharing.deepLink(profile: profile, password: "only-in-memory")
        let two = try ProxyProfileSharing.deepLink(profile: profile, password: "only-in-memory")
        XCTAssertEqual(one.absoluteString, two.absoluteString)
        // A QR link intentionally includes plaintext credentials. It must
        // never be generated before explicit sender confirmation.
        XCTAssertTrue(one.absoluteString.contains("only-in-memory"))
        XCTAssertEqual(try ProxyImport.parse(
            ProxyImport.fromDeepLink(one))[0].password, "only-in-memory")
    }
}
