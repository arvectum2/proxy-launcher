import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class VLESSRealityShareLinkTests: XCTestCase {
    private let base = "vless://12345678-abcd-abcd-abcd-123456789abc@example.com:443" +
        "?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome" +
        "&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=abcd" +
        "&flow=xtls-rprx-vision#My%20Server"

    func testValidRealisticLinkParsesWithoutActivation() throws {
        let item = try VLESSRealityShareLink.parse(base)
        XCTAssertEqual(item.serverHost, "example.com")
        XCTAssertEqual(item.serverPort, 443)
        XCTAssertEqual(item.serverName, "example.com")
        XCTAssertEqual(item.fingerprint, "chrome")
        XCTAssertEqual(item.name, "My Server")
        XCTAssertEqual(item.publicKey.count, 32)
        XCTAssertEqual(item.shortID, "abcd")
        XCTAssertEqual(item.userID.uuidString.lowercased(), "12345678-abcd-abcd-abcd-123456789abc")
        XCTAssertTrue(item.visionFlow)
    }

    func testPinnedLibXrayCGoRequestContract() throws {
        let candidate = try VLESSRealityShareLink.parse(base)
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: candidate.conversionRequest()) as? [String: Any])
        XCTAssertEqual(request["apiVersion"] as? Int, 3)
        XCTAssertEqual(request["method"] as? String, "convertShareLinksToXrayJson")
        let payload = try XCTUnwrap(request["payload"] as? [String: String])
        XCTAssertEqual(payload["text"], base)
        XCTAssertFalse(request.keys.contains("password"))
    }

    func testUnsupportedVariantsFailClosed() {
        for text in [
            base.replacingOccurrences(of: "type=tcp", with: "type=ws"),
            base.replacingOccurrences(of: "security=reality", with: "security=tls"),
            base.replacingOccurrences(of: "encryption=none", with: "encryption=aes-128-gcm"),
            base.replacingOccurrences(of: "&flow=xtls-rprx-vision", with: "&flow=unsupported"),
            base.replacingOccurrences(of: "#My%20Server", with: "&allowInsecure=1#My%20Server"),
            base.replacingOccurrences(of: "#My%20Server", with: "&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA#My%20Server"),
            base.replacingOccurrences(of: "fp=chrome", with: "fp=not-a-browser"),
            base.replacingOccurrences(of: "sid=abcd", with: "sid=abc"),
        ] {
            XCTAssertThrowsError(try VLESSRealityShareLink.parse(text), "Unsupported link accepted")
        }
    }

    func testMalformedUUIDPublicKeyHostAndPortRejected() {
        for text in [
            base.replacingOccurrences(of: "12345678-abcd-abcd-abcd-123456789abc", with: "not-a-uuid"),
            base.replacingOccurrences(of: "443", with: "0"),
            base.replacingOccurrences(of: "example.com:443", with: ":443"),
            base.replacingOccurrences(of: "pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", with: "pbk=wrong"),
            base.replacingOccurrences(of: "sni=example.com", with: "sni=localhost"),
            base.replacingOccurrences(of: "sid=abcd", with: "sid=zz"),
            "https://example.com:443",
        ] {
            XCTAssertThrowsError(try VLESSRealityShareLink.parse(text))
        }
    }

    func testExistingProxyImporterNeverMislabeledVLESSAsHTTP() {
        XCTAssertThrowsError(try ProxyImport.parse(base))
    }

    func testBoundsAndNewlinesAreRejected() {
        XCTAssertThrowsError(try VLESSRealityShareLink.parse(base + "\nvless://other"))
        XCTAssertThrowsError(try VLESSRealityShareLink.parse(String(repeating: "x", count: 4_097)))
    }
}
