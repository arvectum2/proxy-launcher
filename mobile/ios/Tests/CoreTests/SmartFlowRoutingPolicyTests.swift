import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class SmartFlowRoutingPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSharedCDNAddressNeverAuthorizesUnrelatedHostname() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com", html: ["assets.example.com"], network: [], at: now)
        try graph.set(.approved, parent: "example.com", child: "assets.example.com")
        let policy = try SmartFlowRoutingPolicy(manual: ["example.com"], graph: graph, at: now)
        XCTAssertEqual(policy.decide(host: "assets.example.com", resolvedIP: "203.0.113.12"), .direct)
        XCTAssertEqual(policy.decide(host: "tracker.other.test", resolvedIP: "203.0.113.12"), .proxy)
        XCTAssertEqual(policy.decide(host: nil, resolvedIP: "203.0.113.12"), .proxy)
    }

    func testSharedAppleCDNPhysicalIPv4AndIPv6NeverAuthorizeNeighborHost() throws {
        // This is a deterministic *policy* test, not proof of physical
        // packet-tunnel routing on the iPhone. A separate host may resolve
        // to the same real CDN address, but must never inherit DIRECT.
        let policy = try SmartFlowRoutingPolicy(manual: ["www.apple.com"],
                                                 graph: .init(), at: now)
        for physicalIP in ["23.12.156.37", "2001:db8::37"] {
            XCTAssertEqual(policy.decide(host: "www.apple.com",
                                         resolvedIP: physicalIP), .direct)
            XCTAssertEqual(policy.decide(host: "www.apple.com.cn",
                                         resolvedIP: physicalIP), .proxy)
            XCTAssertEqual(policy.decide(host: "www.apple.com.edgekey.net",
                                         resolvedIP: physicalIP), .proxy)
            XCTAssertEqual(policy.decide(host: nil,
                                         resolvedIP: physicalIP), .proxy)
            XCTAssertEqual(policy.decide(host: physicalIP,
                                         resolvedIP: physicalIP), .proxy)
        }
    }

    func testApprovedButOrphanedOrExpiredHostMustRemainProxied() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com", html: ["cdn.example.com"], network: [], at: now)
        try graph.set(.approved, parent: "example.com", child: "cdn.example.com")
        let orphan = try SmartFlowRoutingPolicy(manual: [], graph: graph, at: now)
        XCTAssertEqual(orphan.decide(host: "cdn.example.com", resolvedIP: nil), .proxy)
        let expired = try SmartFlowRoutingPolicy(manual: ["example.com"], graph: graph,
                                                 at: now.addingTimeInterval(SmartExclusionGraph.ttl + 1))
        XCTAssertEqual(expired.decide(host: "cdn.example.com", resolvedIP: nil), .proxy)
    }

    func testUnknownHostAndSyntacticallyInvalidHostnameFailClosed() throws {
        let policy = try SmartFlowRoutingPolicy(manual: ["example.com"], graph: .init(), at: now)
        XCTAssertEqual(policy.decide(host: "evil.example.com", resolvedIP: nil), .proxy)
        XCTAssertEqual(policy.decide(host: "example.com.evil.test", resolvedIP: nil), .proxy)
        XCTAssertEqual(policy.decide(host: "203.0.113.1", resolvedIP: "203.0.113.1"), .proxy)
        XCTAssertEqual(policy.decide(host: "www.example.com", resolvedIP: nil), .direct)
    }
}
