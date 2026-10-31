import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class SmartExclusionGraphTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNoImplicitApprovalAndUnrelatedBlocked() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "www.example.com", html: ["cdn.example.com", "tracking.bad.com"],
                          network: ["api.example.com", "cdn.example.com"], at: now)
        XCTAssertEqual(graph.approved(at: now), [])
        XCTAssertEqual(graph.edges.map(\.host), ["api.example.com", "cdn.example.com"])
        XCTAssertEqual(graph.edges.last?.evidence, .both)
        try graph.set(.approved, parent: "example.com", child: "cdn.example.com")
        XCTAssertEqual(try graph.effective(manual: ["manual.test"], at: now), ["manual.test"])
        XCTAssertEqual(try graph.effective(manual: ["example.com", "manual.test"], at: now), ["cdn.example.com", "example.com", "manual.test"])
    }

    func testPreservesRejectionOnRescan() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com", html: ["cdn.example.com"], network: [], at: now)
        try graph.set(.rejected, parent: "example.com", child: "cdn.example.com")
        try graph.observe(parent: "example.com", html: [], network: ["cdn.example.com"], at: now.addingTimeInterval(5))
        XCTAssertEqual(graph.edges.first?.decision, .rejected)
        XCTAssertEqual(graph.edges.first?.evidence, .network)
    }

    func testExpirationAndCorruptedChildFailClosed() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com", html: ["cdn.example.com"], network: [], at: now)
        try graph.set(.approved, parent: "example.com", child: "cdn.example.com")
        XCTAssertEqual(graph.approved(at: now.addingTimeInterval(SmartExclusionGraph.ttl + 1)), [])
        graph.edges.append(.init(parent: "example.com", host: "unrelated.test", evidence: .network,
                                 decision: .approved, lastSeen: now))
        XCTAssertEqual(graph.approved(at: now), ["cdn.example.com"])
    }

    func testRemovalIsParentScopedAndPreservesManualEntries() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "one.example.com", html: ["cdn.one.example.com"], network: [], at: now)
        try graph.observe(parent: "two.example.com", html: ["cdn.two.example.com"], network: [], at: now)
        try graph.set(.approved, parent: "one.example.com", child: "cdn.one.example.com")
        try graph.set(.approved, parent: "two.example.com", child: "cdn.two.example.com")
        graph.remove(parent: "one.example.com")
        XCTAssertEqual(try graph.effective(manual: ["manual.test", "two.example.com"], at: now),
                       ["cdn.two.example.com", "manual.test", "two.example.com"])
    }

    func testDuplicateConflictingDecisionFailsClosed() throws {
        var graph = SmartExclusionGraph()
        let edge = SmartDependency(parent: "example.com", host: "cdn.example.com", evidence: .both,
                                   decision: .approved, lastSeen: now)
        graph.edges = [edge, .init(parent: edge.parent, host: edge.host, evidence: .network,
                                  decision: .rejected, lastSeen: now)]
        XCTAssertEqual(graph.pruned(at: now).edges.first?.decision, .pending)
        XCTAssertEqual(try graph.effective(manual: ["example.com"], at: now), ["example.com"])
    }

    func testSameHostSharedAcrossTwoApprovedParentsSurvivesOneRemoval() throws {
        var graph = SmartExclusionGraph()
        let host = "cdn.sub.example.com"
        graph.edges = [
            .init(parent: "example.com", host: host, evidence: .html, decision: .approved, lastSeen: now),
            .init(parent: "sub.example.com", host: host, evidence: .network, decision: .approved, lastSeen: now),
        ]
        graph.remove(parent: "example.com")
        XCTAssertEqual(try graph.effective(manual: ["example.com", "sub.example.com"], at: now),
                       [host, "example.com", "sub.example.com"])
    }

    func testBoundsAndRoundtrip() throws {
        var graph = SmartExclusionGraph()
        let oversized = (0..<25).map { "s\($0).example.com" }
        XCTAssertThrowsError(try graph.observe(parent: "example.com", html: oversized, network: [], at: now))
        XCTAssertEqual(graph.edges.count, 0)
        try graph.observe(parent: "example.com", html: ["cdn.example.com"], network: [], at: now)
        let data = try JSONEncoder().encode(graph)
        XCTAssertEqual(try JSONDecoder().decode(SmartExclusionGraph.self, from: data), graph)
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("https://"))
    }
}
