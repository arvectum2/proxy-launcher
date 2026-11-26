import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativeWireGuardRuntimeConfigTests: XCTestCase {
    private let local = Data(repeating: 17,count:32).base64EncodedString()
    private let remote = Data(repeating: 34,count:32).base64EncodedString()
    private let awg = "Jc = 0\nJmin = 0\nJmax = 0\nS1 = 15\nS2 = 18\nH1 = 123456\nH2 = 67543\nH3 = 123123\nH4 = 32345"
    private func profile(_ extra: String = "") -> String {
        """
        [Interface]
        PrivateKey = \(local)
        Address = 10.0.0.2/32, fd00::2/128
        DNS = 192.0.2.53
        MTU = 1420
        \(extra)
        [Peer]
        PublicKey = \(remote)
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = 192.0.2.42:51820
        PersistentKeepalive = 25
        """
    }
    func testWGConfigurationAndRedactedDiagnostics() throws {
        let r = try NativeWireGuardRuntimeConfig.compile(profile(),expected:.wireGuard)
        XCTAssertEqual(r.provider,.rustXray); XCTAssertEqual(r.mtu,1420)
        let config = try r.withEngineConfiguration { try XCTUnwrap(JSONSerialization.jsonObject(with:$0) as? [String:Any]) }
        let inbound = try XCTUnwrap(config["inbounds"] as? [[String:Any]])
        let outbound = try XCTUnwrap(config["outbounds"] as? [[String:Any]])
        XCTAssertEqual(inbound.count,1); XCTAssertEqual(inbound[0]["listen"] as? String,"127.0.0.1")
        XCTAssertEqual(outbound.count,1); XCTAssertEqual(outbound[0]["protocol"] as? String,"wireguard")
        XCTAssertEqual(r.dnsServers,["192.0.2.53"])
        XCTAssertFalse(String(reflecting:r).contains(local))
        XCTAssertFalse(String(reflecting:try WGQuickConfigurationPreview.validated(profile())).contains(local))
        XCTAssertEqual(Mirror(reflecting:r).children.count,0)
    }
    func testAWGConfiguration() throws {
        let r = try NativeWireGuardRuntimeConfig.compile(profile(awg),expected:.amneziaWG1)
        XCTAssertEqual(r.provider,.standaloneAWG)
        let text = r.withEngineConfiguration { String(decoding:$0,as:UTF8.self) }
        XCTAssertTrue(text.contains("h1=123456\n")); XCTAssertTrue(text.hasSuffix("allowed_ip=::/0\n"))
        XCTAssertTrue(text.contains("persistent_keepalive_interval=25\n"))
    }
    func testRejectMismatchAndPartialRoutes() {
        XCTAssertThrowsError(try NativeWireGuardRuntimeConfig.compile(profile(awg),expected:.wireGuard))
        XCTAssertThrowsError(try NativeWireGuardRuntimeConfig.compile(profile(awg),expected:.amneziaWG2))
        XCTAssertThrowsError(try NativeWireGuardRuntimeConfig.compile(profile(),expected:.amneziaWG1))
        XCTAssertThrowsError(try NativeWireGuardRuntimeConfig.compile(profile().replacingOccurrences(of:"0.0.0.0/0, ::/0",with:"0.0.0.0/0"),expected:.wireGuard))
        XCTAssertThrowsError(try NativeWireGuardRuntimeConfig.compile(profile().replacingOccurrences(of:"1420",with:"1200"),expected:.wireGuard))
    }
    func testRejectUnsupportedDNSAndEndpoints() {
        let cases = [profile().replacingOccurrences(of:"DNS = 192.0.2.53",with:""), profile().replacingOccurrences(of:"192.0.2.42",with:"example.invalid"), profile("ListenPort = 1234"), profile().replacingOccurrences(of:local,with:Data(repeating:0,count:32).base64EncodedString())]
        for item in cases {
            XCTAssertThrowsError(try NativeWireGuardRuntimeConfig.compile(item,expected:.wireGuard))
        }
        XCTAssertThrowsError(try NativeWireGuardRuntimeConfig.compile(profile(),expected:.wireGuard,socksPort:80))
    }
    func testIPv6EndpointAndNoPSK() throws {
        let r = try NativeWireGuardRuntimeConfig.compile(profile().replacingOccurrences(of:"192.0.2.42",with:"[2001:db8::42]"),expected:.wireGuard)
        XCTAssertEqual(r.remoteEndpoint,"[2001:db8::42]:51820")
        XCTAssertFalse(r.withEngineConfiguration { String(decoding:$0,as:UTF8.self).contains("preSharedKey") })
    }
    func testProductionStillDenied() throws {
        let r = try NativeWireGuardRuntimeConfig.compile(profile(),expected:.wireGuard)
        XCTAssertThrowsError(try TransportBackendPlan.prepare(profileID:UUID(),revision:UUID(),protocol:r.wireProtocol,scope:.production,routes:.tunnelOnly,required:[.tcpIPv4]))
    }
}
