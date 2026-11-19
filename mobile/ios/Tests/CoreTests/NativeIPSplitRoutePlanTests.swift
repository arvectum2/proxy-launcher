import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativeIPSplitRoutePlanTests:XCTestCase {
    private func base(_ provider:TransportProvider = .rustXray,remote:String="192.0.2.42",dns:[String]=["192.0.2.53","fd00::53"],v4:String="10.0.0.2",v6:String="fd00::2",mtu:Int=1280)->NativeTunnelRoutePlan {
        .init(provider:provider,ipv4Address:v4,ipv6Address:v6,remoteAddress:remote,remotePort:51820,dnsServers:dns,mtu:mtu)
    }
    func testLiteralCanonicalizationAndMasks()throws {
        for (raw,canonical,mask) in [("198.51.100.7","198.51.100.7/32","255.255.255.255"),("198.51.100.0/24","198.51.100.0/24","255.255.255.0"),("198.51.100.128/25","198.51.100.128/25","255.255.255.128"),("192.0.0.0/3","192.0.0.0/3","224.0.0.0")] {
            let p=try NativeLiteralIPPrefix(raw);XCTAssertEqual(p.description,canonical);XCTAssertEqual(p.ipv4Mask,mask)
        }
        XCTAssertEqual(try NativeLiteralIPPrefix("2001:0DB8:0000:0000:0000:0000:0000:0001").description,"2001:db8::1/128")
        XCTAssertEqual(try NativeLiteralIPPrefix("2001:db8:abcd::/48").description,"2001:db8:abcd::/48")
        XCTAssertNil(try NativeLiteralIPPrefix("fc00::/7").ipv4Mask)
    }
    func testRejectMalformedAndSpecialEntireRanges()throws {
        for raw in ["example.com","https://198.51.100.7","198.51.100.7\u{0}suffix"," 198.51.100.7","198.51.100.7/","198.51.100.7/032","198.51.100.7/33","198.51.100.7/0","198.51.100.7/24","198.51.100.1/24/32","2001:db8::1/64","2001:db8::/129","2001:db8::%en0","0.0.0.0/1","64.0.0.0/2","168.0.0.0/7","224.0.0.0/3","127.0.0.1","169.254.0.0/16","255.255.255.255","::/1","::1","::ffff:192.0.2.42","fe80::/10","ff00::/8","fc00::/6"] {
            XCTAssertThrowsError(try NativeLiteralIPPrefix(raw),raw)
        }
    }
    func testOverlapsOnNonByteBoundaryAndAddressFamilies()throws {
        let p=try NativeLiteralIPPrefix("198.51.100.128/25")
        XCTAssertTrue(p.overlaps(try .init("198.51.100.255")));XCTAssertFalse(p.overlaps(try .init("198.51.100.127")))
        let v=try NativeLiteralIPPrefix("2001:db8:8000::/33")
        XCTAssertTrue(v.overlaps(try .init("2001:db8:ffff::1")));XCTAssertFalse(v.overlaps(try .init("2001:db8:7fff::1")));XCTAssertFalse(v.overlaps(p))
    }
    func testExplicitReviewPreservesBaseAndCanonicalOrder()throws {
        for provider in [TransportProvider.rustXray,.standaloneAWG] {
            let b=base(provider),rules=["2001:db8:99::/48","198.51.100.128/25","198.51.100.0/25"]
            let p=try NativeIPSplitRoutePlan.prepare(base:b,explicitRules:rules,existingPolicy:.tunnelOnly,explicitIPOptIn:true)
            XCTAssertEqual(p.base,b);XCTAssertEqual(p.exclusions.map(\.description),["198.51.100.0/25","198.51.100.128/25","2001:db8:99::/48"])
            XCTAssertEqual(p,try NativeIPSplitRoutePlan.prepare(base:b,explicitRules:Array(rules.reversed()),existingPolicy:.tunnelOnly,explicitIPOptIn:true))
            XCTAssertTrue(b.excludedRoutes.isEmpty);XCTAssertEqual(p.base.dnsMatchDomains,[""])
        }
    }
    func testRejectExistingPolicyAndMissingConsent()throws {
        let b=base();for policy in [NativeRoutingAdmission.siteExclusions,.dependencyPolicy,.normallyOff,.malformed] {
            XCTAssertThrowsError(try NativeIPSplitRoutePlan.prepare(base:b,explicitRules:["198.51.100.7"],existingPolicy:policy,explicitIPOptIn:true)) {XCTAssertEqual($0 as? NativeIPSplitRoutePlan.Failure,.existingPolicyConflict)}
        }
        XCTAssertThrowsError(try NativeIPSplitRoutePlan.prepare(base:b,explicitRules:["198.51.100.7"],existingPolicy:.tunnelOnly,explicitIPOptIn:false))
        XCTAssertThrowsError(try NativeIPSplitRoutePlan.prepare(base:b,explicitRules:[],existingPolicy:.tunnelOnly,explicitIPOptIn:true))
        XCTAssertThrowsError(try NativeIPSplitRoutePlan.prepare(base:b,explicitRules:Array(repeating:"198.51.100.7",count:65),existingPolicy:.tunnelOnly,explicitIPOptIn:true))
    }
    func testRejectOverlapAndProtectedAddressesIncludingIPv6Aliases()throws {
        let b=base()
        for rules in [["198.51.100.7","198.51.100.7/32"],["198.51.100.0/24","198.51.100.128/25"],["2001:db8:99::1","2001:0db8:0099:0:0:0:0:1/128"]] {
            XCTAssertThrowsError(try NativeIPSplitRoutePlan.prepare(base:b,explicitRules:rules,existingPolicy:.tunnelOnly,explicitIPOptIn:true)){XCTAssertEqual($0 as? NativeIPSplitRoutePlan.Failure,.overlap)}
        }
        for raw in ["192.0.2.42","192.0.2.0/24","192.0.2.53","10.0.0.0/24","fd00::/64","FD00:0:0:0:0:0:0:53"] {
            XCTAssertThrowsError(try NativeIPSplitRoutePlan.prepare(base:b,explicitRules:[raw],existingPolicy:.tunnelOnly,explicitIPOptIn:true)){XCTAssertEqual($0 as? NativeIPSplitRoutePlan.Failure,.protectedAddress)}
        }
        XCTAssertThrowsError(try NativeIPSplitRoutePlan.prepare(base:base(remote:"2001:db8:9::1"),explicitRules:["2001:db8:9::/48"],existingPolicy:.tunnelOnly,explicitIPOptIn:true))
    }
    func testRejectInvalidSyntheticBaseAndKeepProductionDenied()throws {
        for b in [base(dns:[]),base(dns:["192.0.2.42"]),base(dns:["192.0.2.53","192.0.2.53"]),base(v4:"fd00::4"),base(v6:"10.0.0.5"),base(v6:"FD00::2"),base(mtu:1200)] {
            XCTAssertThrowsError(try NativeIPSplitRoutePlan.prepare(base:b,explicitRules:["198.51.100.7"],existingPolicy:.tunnelOnly,explicitIPOptIn:true))
        }
        XCTAssertThrowsError(try TransportBackendPlan.prepare(profileID:UUID(),revision:UUID(),protocol:.wireGuard,scope:.production,routes:.exclusions,required:[.tcpIPv4]))
    }
}
