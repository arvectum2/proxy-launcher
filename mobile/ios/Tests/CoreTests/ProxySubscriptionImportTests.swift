import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProxySubscriptionImportTests: XCTestCase {
    func testHTTPSSourceAndQueryTokenAreAcceptedOnlyAsUserProvided() throws {
        let url = try ProxySubscriptionImport.sourceURL(" https://feed.example.com/proxies?token=opaque_123 ")
        XCTAssertEqual(url.host, "feed.example.com")
        XCTAssertEqual(url.query, "token=opaque_123")
    }

    func testUnsafeSourcesFailClosed() {
        let unsafe = [
            "http://feed.example.com/list", "https://127.0.0.1/list",
            "https://192.168.0.1/proxies", "https://localhost/proxies",
            "https://feed.local/proxies", "https://feed.internal/list",
            "https://feed.example.com:8080/list",
            "https://user:pass@feed.example.com/list",
            "https://feed.example.com/list#fragment",
            "https://feed.example.com\n.evil.com/list",
        ]
        for text in unsafe {
            XCTAssertThrowsError(try ProxySubscriptionImport.sourceURL(text), text)
        }
    }

    func testRawAndBase64SupplierLists() throws {
        let list = "http://one.example.com:8080\nsocks5://bob:pass@two.example.com:1080"
        let raw = try ProxySubscriptionImport.decode(Data(list.utf8))
        XCTAssertEqual(try ProxyImport.parse(raw).count, 2)
        let encoded = Data(list.utf8).base64EncodedString()
        let decoded = try ProxySubscriptionImport.decode(Data(encoded.utf8))
        XCTAssertEqual(try ProxyImport.parse(decoded).map(\.type), [.http, .socks5])
    }

    func testUnsupportedProtocolCannotBecomePartialImport() {
        for list in ["http://one.example.com:8080\nvless://uuid@other.example.com:443",
                     "wg://vpn.example.com:51820",
                     "not-a-supported-subscription"] {
            XCTAssertThrowsError(try ProxySubscriptionImport.decode(Data(list.utf8)))
            let encoded = Data(list.utf8).base64EncodedString()
            XCTAssertThrowsError(try ProxySubscriptionImport.decode(Data(encoded.utf8)))
        }
    }

    func testPayloadLimitsAndInvalidUTF8() {
        XCTAssertThrowsError(try ProxySubscriptionImport.decode(Data(repeating: 65, count: 256_001)))
        XCTAssertThrowsError(try ProxySubscriptionImport.decode(Data([0xff, 0xfe])))
        XCTAssertThrowsError(try ProxySubscriptionImport.decode(Data([0x00, 0x41])))
        XCTAssertThrowsError(try ProxySubscriptionImport.sourceURL(String(repeating: "a", count: 2049)))
    }
}
