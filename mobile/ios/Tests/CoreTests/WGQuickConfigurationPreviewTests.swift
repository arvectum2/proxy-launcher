import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class WGQuickConfigurationPreviewTests: XCTestCase {
    private let privateKey = Data(repeating: 0x11, count: 32).base64EncodedString()
    private let publicKey = Data(repeating: 0x22, count: 32).base64EncodedString()
    private let preshared = Data(repeating: 0x33, count: 32).base64EncodedString()

    private func standard(_ extra: String = "", peerExtra: String = "") -> String {
        """
        [Interface]
        PrivateKey = \(privateKey)
        Address = 10.0.0.2/32, fd00::2/128
        DNS = 1.1.1.1, 2606:4700:4700::1111
        MTU = 1420
        \(extra)
        [Peer]
        PublicKey = \(publicKey)
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = example.com:51820
        PresharedKey = \(preshared)
        PersistentKeepalive = 25
        \(peerExtra)
        """
    }

    func testStandardWireGuardPreviewNeverExposesPrivateKeys() throws {
        let preview = try WGQuickConfigurationPreview.parse(standard())
        XCTAssertEqual(preview.format, .wireGuard)
        XCTAssertEqual(preview.addresses, ["10.0.0.2/32", "fd00::2/128"])
        XCTAssertEqual(preview.dnsServers.count, 2)
        XCTAssertEqual(preview.peers.count, 1)
        XCTAssertEqual(preview.peers[0].endpoint, "example.com:51820")
        XCTAssertEqual(preview.peers[0].allowedIPs, ["0.0.0.0/0", "::/0"])
        XCTAssertTrue(preview.peers[0].hasPresharedKey)
        let rendered = String(reflecting: preview)
        XCTAssertFalse(rendered.contains(privateKey))
        XCTAssertFalse(rendered.contains(publicKey))
        XCTAssertFalse(rendered.contains(preshared))
    }

    func testBracketedIPv6EndpointAndNoDNS() throws {
        let profile = """
        [Interface]
        PrivateKey = \(privateKey)
        Address = 192.0.2.3/32
        [Peer]
        PublicKey = \(publicKey)
        AllowedIPs = 192.0.2.0/24
        Endpoint = [2001:db8::3]:51820
        """
        let item = try WGQuickConfigurationPreview.parse(profile)
        XCTAssertEqual(item.peers.first?.endpoint, "[2001:db8::3]:51820")
        XCTAssertTrue(item.dnsServers.isEmpty)
        XCTAssertFalse(item.peers[0].hasPresharedKey)
    }

    func testAmneziaWG1RequiresCompleteValidParameters() throws {
        let awg = """
        Jc = 3
        Jmin = 32
        Jmax = 120
        S1 = 72
        S2 = 82
        H1 = 1282
        H2 = 1283
        H3 = 1284
        H4 = 1285
        """
        let result = try WGQuickConfigurationPreview.parse(standard(awg))
        XCTAssertEqual(result.format, .amneziaWG1)
        XCTAssertThrowsError(try WGQuickConfigurationPreview.parse(standard("Jc = 3")))
        XCTAssertThrowsError(try WGQuickConfigurationPreview.parse(
            standard(awg.replacingOccurrences(of: "H4 = 1285", with: "H4 = 1282"))))
        XCTAssertThrowsError(try WGQuickConfigurationPreview.parse(
            standard(awg.replacingOccurrences(of: "S2 = 82", with: "S2 = 128"))))
    }

    func testNoAWG2Or3DowngradeToWG1() {
        for item in ["S3 = 42", "S4 = 12", "I1 = <r 120>",
                     "HeaderProtectionKey = deadbeef", "RandomTrailers = 1"] {
            XCTAssertThrowsError(try WGQuickConfigurationPreview.parse(standard(item)))
        }
    }

    func testRejectsUnsupportedShellHooksAndConflicts() {
        for item in ["PostUp = rm -rf /", "PreDown = echo hello",
                     "PrivateKey = \(privateKey)", "Table = auto",
                     "S1 = 24"] {
            XCTAssertThrowsError(try WGQuickConfigurationPreview.parse(standard(item)))
        }
        XCTAssertThrowsError(try WGQuickConfigurationPreview.parse(
            standard().replacingOccurrences(of: "[Peer]", with: "[Interface]")))
    }

    func testRejectsMalformedKeysCIDRAndEndpoint() {
        let invalids = [
            standard().replacingOccurrences(of: privateKey, with: "not-a-key"),
            standard().replacingOccurrences(of: "fd00::2/128", with: "fd00::2/129"),
            standard().replacingOccurrences(of: "10.0.0.2/32", with: "10.0.0.999/24"),
            standard().replacingOccurrences(of: "example.com:51820", with: "example.com:0"),
            standard().replacingOccurrences(of: "example.com:51820", with: "user@host:443"),
            standard().replacingOccurrences(of: "AllowedIPs = 0.0.0.0/0, ::/0",
                                            with: "AllowedIPs = 0.0.0.0"),
        ]
        for entry in invalids { XCTAssertThrowsError(try WGQuickConfigurationPreview.parse(entry)) }
    }

    func testRejectsOversizeAndNulByte() {
        XCTAssertThrowsError(try WGQuickConfigurationPreview.parse(
            String(repeating: "X", count: 16_385)))
        XCTAssertThrowsError(try WGQuickConfigurationPreview.parse(standard() + "\0"))
    }
}
