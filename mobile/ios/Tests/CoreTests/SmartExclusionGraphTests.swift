import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class SmartExclusionGraphTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAutoApprovesOnlyStrongObservedFirstPartyNotUnrelatedOrWeak() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com",
                          html: ["cdn.example.com", "weak.example.com", "third-party.test"],
                          network: ["cdn.example.com", "xhr.example.com", "third-party.test"], at: now)
        XCTAssertEqual(graph.approveStrongFirstParty(parent: "example.com", manual: ["example.com"], at: now),
                       ["cdn.example.com"])
        XCTAssertEqual(try graph.effective(manual: ["example.com"], at: now),
                       ["cdn.example.com", "example.com"])
        XCTAssertEqual(Set(graph.edges.filter { $0.decision == .pending }.map(\.host)),
                       Set(["weak.example.com", "xhr.example.com"]))
    }

    func testFirstPartyTrackingEndpointsAreSuggestedButNotAutomaticallyBypassed() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com",
                          html: ["api.example.com", "analytics.example.com", "pixel.example.com"],
                          network: ["api.example.com", "analytics.example.com", "pixel.example.com"], at: now)
        XCTAssertEqual(graph.approveStrongFirstParty(parent: "example.com", manual: ["example.com"], at: now),
                       ["api.example.com"])
        XCTAssertEqual(Set(graph.edges.filter { $0.decision == .pending }.map(\.host)),
                       Set(["analytics.example.com", "pixel.example.com"]))
    }

    func testWWWManualRootAlsoAllowsSameSiteStrongAutoApprovals() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "www.example.com", html: ["api.example.com"],
                          network: ["api.example.com"], at: now)
        XCTAssertEqual(graph.approveStrongFirstParty(parent: "www.example.com",
                                                      manual: ["www.example.com"], at: now),
                       ["api.example.com"])
        XCTAssertEqual(try graph.effective(manual: ["www.example.com"], at: now),
                       ["api.example.com", "www.example.com"])
    }

    func testAutoApprovalNeverOverwritesRejectedOrRemovesExplicitDecision() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com", html: ["blocked.example.com", "ok.example.com"],
                          network: ["blocked.example.com", "ok.example.com"], at: now)
        try graph.set(.rejected, parent: "example.com", child: "blocked.example.com")
        XCTAssertEqual(graph.approveStrongFirstParty(parent: "example.com", manual: ["example.com"], at: now),
                       ["ok.example.com"])
        try graph.observe(parent: "example.com", html: ["blocked.example.com"],
                          network: ["blocked.example.com"], at: now.addingTimeInterval(2))
        XCTAssertTrue(graph.approveStrongFirstParty(parent: "example.com", manual: ["example.com"], at: now.addingTimeInterval(2)).isEmpty)
        XCTAssertEqual(graph.edges.first(where: { $0.host == "blocked.example.com" })?.decision, .rejected)
        XCTAssertEqual(graph.approveStrongFirstParty(parent: "example.com", manual: ["other.test"], at: now), [])
    }

    func testAutoApprovalBoundedByThirtyTwoActiveExclusions() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com", html: ["cdn.example.com"],
                          network: ["cdn.example.com"], at: now)
        let manual = ["example.com"] + (0..<31).map { "site\($0).test" }
        XCTAssertEqual(graph.approveStrongFirstParty(parent: "example.com", manual: manual, at: now), [])
        XCTAssertEqual(graph.edges.first?.decision, .pending)
    }

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

    func testExplicitExternalLinkStaysParentScopedPastDiscoveryExpiry() throws {
        var graph = SmartExclusionGraph()
        try graph.addUserLink(parent: "example.com", child: "login.partner.test", at: now)
        XCTAssertEqual(try graph.effective(manual: ["example.com"], at: now),
                       ["example.com", "login.partner.test"])
        XCTAssertEqual(try graph.effective(manual: ["other.test"], at: now), ["other.test"])
        XCTAssertEqual(try graph.effective(manual: ["example.com"],
                                           at: now.addingTimeInterval(10 * 86400)),
                       ["example.com", "login.partner.test"])
        try graph.set(.rejected, parent: "example.com", child: "login.partner.test")
        XCTAssertEqual(try graph.effective(manual: ["example.com"], at: now), ["example.com"])
        let restored = try JSONDecoder().decode(SmartExclusionGraph.self,
                                                 from: JSONEncoder().encode(graph))
        XCTAssertEqual(restored.pruned(at: now.addingTimeInterval(10 * 86400)).edges.count, 1)
    }

    func testUserDenialSurvivesRescanAndExpiration() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com", html: ["auth.example.com"],
                          network: ["auth.example.com"], at: now)
        try graph.set(.rejected, parent: "example.com", child: "auth.example.com")
        try graph.observe(parent: "example.com", html: ["auth.example.com"],
                          network: ["auth.example.com"], at: now.addingTimeInterval(8 * 86400))
        XCTAssertTrue(graph.approveStrongFirstParty(parent: "example.com",
                                                     manual: ["example.com"],
                                                     at: now.addingTimeInterval(8 * 86400)).isEmpty)
        XCTAssertEqual(try graph.effective(manual: ["example.com"],
                                           at: now.addingTimeInterval(8 * 86400)),
                       ["example.com"])
    }

    func testDeletingChildCannotBeUndoneByNextAutomaticScan() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com",
                          html: ["auth.example.com"],
                          network: ["auth.example.com"], at: now)
        XCTAssertEqual(graph.approveStrongFirstParty(parent: "example.com",
                                                      manual: ["example.com"], at: now),
                       ["auth.example.com"])
        graph.remove(parent: "example.com", child: "auth.example.com")
        try graph.observe(parent: "example.com", html: ["auth.example.com"],
                          network: ["auth.example.com"], at: now.addingTimeInterval(60))
        XCTAssertTrue(graph.approveStrongFirstParty(parent: "example.com",
                                                     manual: ["example.com"],
                                                     at: now.addingTimeInterval(60)).isEmpty)
        XCTAssertEqual(try graph.effective(manual: ["example.com"], at: now), ["example.com"])
        // A deliberate Add restores only the selected child.
        try graph.addUserLink(parent: "example.com", child: "auth.example.com",
                              at: now.addingTimeInterval(120))
        XCTAssertEqual(try graph.effective(manual: ["example.com"],
                                           at: now.addingTimeInterval(120)),
                       ["auth.example.com", "example.com"])
    }

    func testExplicitLinkCannotBypassRuleBudget() throws {
        var graph = SmartExclusionGraph()
        for i in 0..<SiteDependencyDiscovery.maxCandidates {
            try graph.addUserLink(parent: "example.com", child: "s\(i).partner.test", at: now)
        }
        XCTAssertThrowsError(try graph.addUserLink(parent: "example.com",
                                                    child: "overflow.partner.test", at: now))
        XCTAssertThrowsError(try graph.addUserLink(parent: "example.com",
                                                    child: "example.com", at: now))
    }

    func testPreviousVersionGraphDecodesWithoutNewOptionalFields() throws {
        let oldData = Data(#"{"edges":[]}"#.utf8)
        let graph = try JSONDecoder().decode(SmartExclusionGraph.self, from: oldData)
        XCTAssertTrue(graph.pruned(at: now).edges.isEmpty)
        XCTAssertTrue((graph.suppressed ?? []).isEmpty)
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
