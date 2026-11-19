import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativeTunnelRoutePlanTests: XCTestCase {
    private func profile(_ endpoint: String = "192.0.2.42:51820", dns: String = "192.0.2.53, fd00::53", addresses: String = "10.0.0.2/32, fd00::2/128", awg: Bool = false) -> String {
        let local = Data(repeating:17,count:32).base64EncodedString()
        let peer = Data(repeating:34,count:32).base64EncodedString()
        let extras = awg ? "Jc=0\nJmin=0\nJmax=0\nS1=15\nS2=18\nH1=123456\nH2=67543\nH3=123123\nH4=32345" : ""
        return """
        [Interface]
        PrivateKey = \(local)
        Address = \(addresses)
        DNS = \(dns)
        MTU = 1280
        \(extras)
        [Peer]
        PublicKey = \(peer)
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = \(endpoint)
        """
    }
    func testBothProvidersUseSameFullTunnelWithoutHostBypass() throws {
        for awg in [false,true] {
            let c = try NativeWireGuardRuntimeConfig.compile(profile(awg:awg),expected:awg ? .amneziaWG1 : .wireGuard)
            let p = try NativeTunnelRoutePlan.prepare(c)
            XCTAssertEqual(p.provider,awg ? .standaloneAWG : .rustXray)
            XCTAssertEqual(p.ipv4Address,"10.0.0.2"); XCTAssertEqual(p.ipv6Address,"fd00::2")
            XCTAssertEqual(p.remoteAddress,"192.0.2.42"); XCTAssertEqual(p.remotePort,51820)
            XCTAssertEqual(p.dnsServers,["192.0.2.53","fd00::53"])
            XCTAssertEqual(p.ipv4DefaultRoutes,["0.0.0.0/0"]); XCTAssertEqual(p.ipv6DefaultRoutes,["::/1","8000::/1"])
            XCTAssertTrue(p.excludedRoutes.isEmpty); XCTAssertEqual(p.dnsMatchDomains,[""])
            XCTAssertEqual(p.underlay,.providerOwnedSocketVerifiedBeforeActivation)
        }
    }
    func testIPv6OuterCanonicalization() throws {
        let c = try NativeWireGuardRuntimeConfig.compile(profile("[2001:0db8:0:0:0:0:0:42]:51820"),expected:.wireGuard)
        XCTAssertEqual(try NativeTunnelRoutePlan.prepare(c).remoteAddress,"2001:db8::42")
    }
    func testRejectPolicyInsteadOfSilentlyDroppingExclusions() throws {
        let c = try NativeWireGuardRuntimeConfig.compile(profile(),expected:.wireGuard)
        for policy: TransportBackendPlan.RoutePolicy in [.directFallback,.exclusions] {
            XCTAssertThrowsError(try NativeTunnelRoutePlan.prepare(c,routes:policy))
        }
        XCTAssertThrowsError(try NativeTunnelRoutePlan.prepare(c,siteExclusions:["example.invalid"]))
        XCTAssertThrowsError(try NativeTunnelRoutePlan.prepare(c,applicationExclusions:["test.bundle"]))
    }
    func testRejectSpecialAddressesInEachRole() throws {
        for ip in ["0.0.0.0","127.0.0.1","169.254.1.2","224.0.0.1","255.255.255.255","::","::1","fe80::1","ff02::1","::ffff:192.0.2.42"] {
            let outer = ip.contains(":") ? "[\(ip)]:51820" : "\(ip):51820"
            XCTAssertThrowsError(try NativeTunnelRoutePlan.prepare(NativeWireGuardRuntimeConfig.compile(profile(outer),expected:.wireGuard)))
            XCTAssertThrowsError(try NativeTunnelRoutePlan.prepare(NativeWireGuardRuntimeConfig.compile(profile(dns:ip),expected:.wireGuard)))
            let local = ip.contains(":") ? "10.0.0.2/32, \(ip)/128" : "\(ip)/32, fd00::2/128"
            XCTAssertThrowsError(try NativeTunnelRoutePlan.prepare(NativeWireGuardRuntimeConfig.compile(profile(addresses:local),expected:.wireGuard)))
        }
    }
    func testRejectSameIPAcrossRolesAndDuplicateDNSAliases() throws {
        for config in [profile("10.0.0.2:51820"),profile("[fd00:0:0:0:0:0:0:2]:51820"),profile(dns:"192.0.2.42"),profile(dns:"10.0.0.2"),profile(dns:"fd00:0:0:0:0:0:0:2"),profile(dns:"fd00::53, fd00:0:0:0:0:0:0:53")] {
            XCTAssertThrowsError(try NativeTunnelRoutePlan.prepare(NativeWireGuardRuntimeConfig.compile(config,expected:.wireGuard)))
        }
    }
    func testRouteObjectDoesNotContainKeysOrUnlockProduction() throws {
        let c = try NativeWireGuardRuntimeConfig.compile(profile(),expected:.wireGuard)
        let r = try NativeTunnelRoutePlan.prepare(c)
        XCTAssertFalse(String(reflecting:r).contains(Data(repeating:17,count:32).base64EncodedString()))
        XCTAssertThrowsError(try TransportBackendPlan.prepare(profileID:UUID(),revision:UUID(),protocol:c.wireProtocol,scope:.production,routes:.tunnelOnly,required:[.dns]))
    }
    func testCommonFullRouteCandidateForAllSupportedKinds() throws {
        let key=Data(repeating:17,count:32).base64EncodedString().replacingOccurrences(of:"=",with:"")
        let vless="vless://12345678-abcd-abcd-abcd-123456789abc@192.0.2.42:443?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk="+key+"&sid=abcd"
        for (kind,source) in [(TransportProtocol.wireGuard,profile()),(.amneziaWG1,profile(awg:true)),(.vlessReality,vless)] {
            let r=try NativeCredentialRecord.create(profileID:UUID(),expected:kind,source:source)
            let p=try r.compileFullTunnelCandidate(admission:.tunnelOnly,exactDNSAvailable:true)
            XCTAssertEqual(p.reference,r.reference)
            XCTAssertEqual(p.route.provider,r.reference.kind.provider)
            XCTAssertEqual(p.validation.remoteAddress,p.route.remoteAddress)
            XCTAssertEqual(p.validation.remotePort,p.route.remotePort)
            XCTAssertEqual(p.route.ipv4DefaultRoutes,["0.0.0.0/0"])
            XCTAssertEqual(p.route.ipv6DefaultRoutes,["::/1","8000::/1"])
            XCTAssertTrue(p.route.excludedRoutes.isEmpty)
            XCTAssertEqual(p.route.dnsMatchDomains,[""])
            XCTAssertEqual(p.exactDNSRequired,kind != .amneziaWG1)
            XCTAssertEqual(Mirror(reflecting:p).children.count,0)
            for blocked in [NativeRoutingAdmission.siteExclusions,.dependencyPolicy,.normallyOff,.malformed] {
                XCTAssertThrowsError(try r.compileFullTunnelCandidate(admission:blocked,exactDNSAvailable:true))
            }
            if kind == .amneziaWG1 {
                XCTAssertNoThrow(try r.compileFullTunnelCandidate(admission:.tunnelOnly,exactDNSAvailable:false))
            } else {
                XCTAssertThrowsError(try r.compileFullTunnelCandidate(admission:.tunnelOnly,exactDNSAvailable:false))
            }
            if kind == .vlessReality {
                XCTAssertEqual(p.route.dnsServers,["1.1.1.1","8.8.8.8"])
                XCTAssertEqual(p.route.ipv4Address,"192.0.2.177")
                XCTAssertEqual(p.route.ipv6Address,"2001:db8:177::2")
                let json=try p.configuration.withEngineConfiguration {try XCTUnwrap(JSONSerialization.jsonObject(with:$0) as? [String:Any])}
                let inbound=try XCTUnwrap((json["inbounds"] as? [[String:Any]])?.first)
                XCTAssertEqual((inbound["settings"] as? [String:Any])?["udp"] as? Bool,true)
                XCTAssertEqual((json["outbounds"] as? [[String:Any]])?.count,1)
            } else {
                XCTAssertEqual(p.route.dnsServers,["192.0.2.53","fd00::53"])
            }
        }
    }

    func testVLESSFullRouteRejectsRemoteLocalOrResolverCollision() throws {
        for address in ["192.0.2.177","1.1.1.1","8.8.8.8","127.0.0.1","::1","example.com"] {
            XCTAssertThrowsError(try NativeTunnelRoutePlan.prepareVLESS(.init(remoteAddress:address,remotePort:443)))
        }
        XCTAssertThrowsError(try NativeTunnelRoutePlan.prepareVLESS(.init(remoteAddress:"192.0.2.42",remotePort:0)))
    }

}
