import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class SmartRouteProvenanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testManualHostAndAliasTakePriorityOverGraph() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com", html: ["assets.example.com"],
                          network: ["assets.example.com"], at: now)
        try graph.set(.approved, parent: "example.com", child: "assets.example.com")
        let policy = try SmartFlowRoutingPolicy(
            manual: ["example.com", "www.example.com"], graph: graph, at: now)
        XCTAssertEqual(policy.explain(host: "example.com", resolvedIP: "203.0.113.10"),
                       .init(disposition: .direct, reason: .manualExclusion))
        XCTAssertEqual(policy.explain(host: "www.example.com", resolvedIP: "203.0.113.10"),
                       .init(disposition: .direct, reason: .manualExclusion))
        XCTAssertEqual(policy.explain(host: "assets.example.com", resolvedIP: "203.0.113.10"),
                       .init(disposition: .direct, reason: .approvedDependency))
        XCTAssertEqual(policy.explain(host: "other.test", resolvedIP: "203.0.113.10"),
                       .init(disposition: .proxy, reason: .noMatchingPermission))
    }

    func testPendingRejectedOrphanedAndExpiredCannotAuthorizeDirect() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com",
                          html: ["pending.example.com", "rejected.example.com",
                                 "approved.example.com"],
                          network: [], at: now)
        try graph.set(.rejected, parent: "example.com", child: "rejected.example.com")
        try graph.set(.approved, parent: "example.com", child: "approved.example.com")
        let active = try SmartFlowRoutingPolicy(
            manual: ["example.com"], graph: graph, at: now)
        for host in ["pending.example.com", "rejected.example.com"] {
            XCTAssertEqual(active.explain(host: host, resolvedIP: nil),
                           .init(disposition: .proxy, reason: .noMatchingPermission))
        }
        XCTAssertEqual(active.explain(host: "approved.example.com", resolvedIP: nil).reason,
                       .approvedDependency)
        let orphan = try SmartFlowRoutingPolicy(manual: [], graph: graph, at: now)
        XCTAssertEqual(orphan.explain(host: "approved.example.com", resolvedIP: nil).disposition,
                       .proxy)
        let expired = try SmartFlowRoutingPolicy(
            manual: ["example.com"], graph: graph,
            at: now.addingTimeInterval(SmartExclusionGraph.ttl + 1))
        XCTAssertEqual(expired.explain(host: "approved.example.com", resolvedIP: nil).disposition,
                       .proxy)
    }

    func testInvalidAndRawIPFailClosedEvenOnSharedIPv4AndIPv6() throws {
        let policy = try SmartFlowRoutingPolicy(manual: ["example.com"],
                                               graph: .init(), at: now)
        let inputs: [String?] = [nil, "2001:db8::12", "203.0.113.12",
                                 "*.example.com", "example.com/path", "bad host"]
        for input in inputs {
            for ip in ["203.0.113.12", "2001:db8::12"] {
                XCTAssertEqual(policy.explain(host: input, resolvedIP: ip),
                               .init(disposition: .proxy, reason: .unverifiedHost))
            }
        }
        XCTAssertEqual(policy.explain(host: "example.com.other.test",
                                      resolvedIP: "2001:db8::12"),
                       .init(disposition: .proxy, reason: .noMatchingPermission))
        XCTAssertEqual(policy.explain(host: "EXAMPLE.COM", resolvedIP: "2001:db8::12"),
                       .init(disposition: .direct, reason: .manualExclusion))
    }

    func testNewReasonPartitionPreservesOriginalLegacyPolicy() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com",
                          html: ["assets.example.com", "pending.example.com"],
                          network: ["assets.example.com"], at: now)
        try graph.set(.approved, parent: "example.com", child: "assets.example.com")
        let manualVariants: [[String]] = [
            [], ["example.com"], ["www.example.com"], ["gosuslugi.ru"],
            ["example.com", "gosuslugi.ru"], ["203.0.113.10"]
        ]
        let hosts: [String?] = [
            "example.com", "EXAMPLE.COM", "www.example.com",
            "assets.example.com", "pending.example.com", "gu-st.ru",
            "www.gosuslugi.ru", "203.0.113.10", "2001:db8::10",
            "unrelated.example.com", "example.com.evil.test", nil
        ]
        for manual in manualVariants {
            for date in [now, now.addingTimeInterval(SmartExclusionGraph.ttl + 1)] {
                let policy = try SmartFlowRoutingPolicy(manual: manual, graph: graph, at: date)
                // Independent reference implementation from Smart3.0 before
                // the introduction of route-reason partitioning.
                let effective = try graph.effective(manual: manual, at: date)
                let permitted = Set(effective.flatMap {
                    SiteExclusionPolicy.routingHosts(for: $0)
                }.filter { SiteDependencyDiscovery.isScannableHost($0) })
                for host in hosts {
                    let legacy: SmartFlowDisposition
                    if let lowered = host?.lowercased(),
                       let normalized = try? SiteExclusionPolicy.normalize(lowered),
                       lowered == normalized,
                       SiteDependencyDiscovery.isScannableHost(lowered),
                       permitted.contains(lowered) {
                        legacy = .direct
                    } else {
                        legacy = .proxy
                    }
                    for ip in [nil, "203.0.113.10", "2001:db8::10"] {
                        XCTAssertEqual(policy.decide(host: host, resolvedIP: ip), legacy,
                                       "Drift for manual=\(manual), host=\(host ?? "<nil>")")
                    }
                }
            }
        }
    }

    func testExplainAndDecideRemainEquivalentForAllCaseInputs() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com", html: ["assets.example.com"],
                          network: [], at: now)
        try graph.set(.approved, parent: "example.com", child: "assets.example.com")
        let policy = try SmartFlowRoutingPolicy(
            manual: ["example.com", "gosuslugi.ru"], graph: graph, at: now)
        let hosts: [String?] = ["example.com", "www.example.com",
                                "assets.example.com", "gu-st.ru",
                                "www.gosuslugi.ru", "other.test", "192.0.2.1", nil]
        for host in hosts {
            for ip in [nil, "203.0.113.1", "2001:db8::1"] {
                let evaluated = policy.explain(host: host, resolvedIP: ip)
                XCTAssertEqual(policy.decide(host: host, resolvedIP: ip),
                               evaluated.disposition)
                XCTAssertFalse(evaluated.reason.rawValue.contains("."))
                XCTAssertFalse(evaluated.reason.rawValue.contains(":"))
            }
        }
        XCTAssertEqual(SmartRouteReason.manualExclusion.rawValue, "MANUAL")
        XCTAssertEqual(SmartRouteReason.approvedDependency.rawValue, "APPROVED")
        XCTAssertEqual(SmartRouteReason.noMatchingPermission.rawValue, "NO_RULE")
        XCTAssertEqual(SmartRouteReason.unverifiedHost.rawValue, "UNVERIFIED_HOST")
    }
}
