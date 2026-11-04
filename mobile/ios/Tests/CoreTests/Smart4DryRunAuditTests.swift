import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class Smart4DryRunAuditTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func policy(_ manual: [String] = []) throws -> SmartFlowRoutingPolicy {
        try SmartFlowRoutingPolicy(manual: manual, graph: .init(), at: now)
    }

    func testDefaultIsDisabledAndRecordsNothingEvenWhenEvidenceIsConfirmed() throws {
        var audit = Smart4DryRunAudit()
        let rule = try policy(["example.com"])
        audit.observe(policy: rule, host: "example.com",
                      resolvedIP: "203.0.113.7", smart3: .confirmedDirect)
        XCTAssertEqual(audit.summary, .init(enabled: false, observed: 0,
            confirmedMatches: 0, confirmedMismatches: 0, inconclusive: 0,
            proposedDirect: 0, proposedProxy: 0, capped: false))
    }

    func testOnlyIndependentConfirmedTransportCountsAsMatchOrMismatch() throws {
        let rule = try policy(["example.com"])
        var audit = Smart4DryRunAudit(optedIn: true)
        audit.observe(policy: rule, host: "example.com",
                      resolvedIP: "203.0.113.7", smart3: .confirmedDirect)
        audit.observe(policy: rule, host: "example.com",
                      resolvedIP: "203.0.113.7", smart3: .confirmedViaProxy)
        XCTAssertEqual(audit.summary.confirmedMatches, 1)
        XCTAssertEqual(audit.summary.confirmedMismatches, 1)
        XCTAssertEqual(audit.summary.proposedDirect, 2)
        XCTAssertEqual(audit.summary.proposedProxy, 0)
    }

    func testApprovedDependencyMustBeLiveAndExplicitlyAuthorized() throws {
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "example.com",
                          html: ["cdn.example.com", "pending.example.com"],
                          network: ["cdn.example.com"], at: now)
        try graph.set(.approved, parent: "example.com", child: "cdn.example.com")
        let live = try SmartFlowRoutingPolicy(manual: ["example.com"],
                                              graph: graph, at: now)
        let expired = try SmartFlowRoutingPolicy(
            manual: ["example.com"], graph: graph,
            at: now.addingTimeInterval(SmartExclusionGraph.ttl + 1))
        var audit = Smart4DryRunAudit(optedIn: true)
        audit.observe(policy: live, host: "cdn.example.com",
                      resolvedIP: "203.0.113.8", smart3: .confirmedDirect)
        audit.observe(policy: live, host: "pending.example.com",
                      resolvedIP: "203.0.113.8", smart3: .confirmedViaProxy)
        audit.observe(policy: expired, host: "cdn.example.com",
                      resolvedIP: "203.0.113.8", smart3: .confirmedViaProxy)
        XCTAssertEqual(audit.summary.confirmedMatches, 3)
        XCTAssertEqual(audit.summary.confirmedMismatches, 0)
        XCTAssertEqual(audit.summary.proposedDirect, 1)
        XCTAssertEqual(audit.summary.proposedProxy, 2)
    }

    func testSharedCDNIPv4HostNamesRemainIndependent() throws {
        let rule = try policy(["example.com"])
        var audit = Smart4DryRunAudit(optedIn: true)
        for (host, evidence) in [
            ("example.com", Smart3TransportEvidence.confirmedDirect),
            ("other.test", Smart3TransportEvidence.confirmedViaProxy)
        ] {
            audit.observe(policy: rule, host: host, resolvedIP: "203.0.113.1",
                          smart3: evidence)
        }
        XCTAssertEqual(audit.summary.confirmedMatches, 2)
        XCTAssertEqual(audit.summary.proposedProxy, 1)
        XCTAssertEqual(audit.summary.proposedDirect, 1)
    }

    func testSharedIPv6AndDNSInferencesAreInconclusiveNotMatches() throws {
        let rule = try policy(["example.com"])
        var audit = Smart4DryRunAudit(optedIn: true)
        audit.observe(policy: rule, host: "example.com",
                      resolvedIP: "2001:db8::3", smart3: .inferredOnlyFromIP)
        audit.observe(policy: rule, host: "unapproved.test",
                      resolvedIP: "2001:0db8:0:0::3", smart3: .unknown)
        XCTAssertEqual(audit.summary.observed, 2)
        XCTAssertEqual(audit.summary.confirmedMatches, 0)
        XCTAssertEqual(audit.summary.confirmedMismatches, 0)
        XCTAssertEqual(audit.summary.inconclusive, 2)
    }

    func testInvalidRawIPAndNilHostFailClosedEvenIfReportedDirect() throws {
        let rule = try policy(["example.com"])
        var audit = Smart4DryRunAudit(optedIn: true)
        for host in [nil, "203.0.113.9", "*.example.com", "example.com/path"] {
            audit.observe(policy: rule, host: host, resolvedIP: "203.0.113.9",
                          smart3: .confirmedDirect)
        }
        XCTAssertEqual(audit.summary.proposedDirect, 0)
        XCTAssertEqual(audit.summary.proposedProxy, 4)
        XCTAssertEqual(audit.summary.confirmedMismatches, 4)
    }

    func testBoundedAccountingAndReOptInClearsAllOldObservations() throws {
        let rule = try policy(["example.com"])
        var audit = Smart4DryRunAudit(optedIn: true)
        for _ in 0..<(Smart4DryRunAudit.maximumSamples + 40) {
            audit.observe(policy: rule, host: "example.com",
                          resolvedIP: nil, smart3: .confirmedDirect)
        }
        XCTAssertEqual(audit.summary.observed, Smart4DryRunAudit.maximumSamples)
        XCTAssertEqual(audit.summary.confirmedMatches, Smart4DryRunAudit.maximumSamples)
        XCTAssertTrue(audit.summary.capped)
        audit.setOptIn(false)
        XCTAssertEqual(audit.summary.observed, 0)
        XCTAssertFalse(audit.summary.capped)
        audit.setOptIn(true)
        XCTAssertEqual(audit.summary.observed, 0)
        XCTAssertEqual(audit.summary.confirmedMatches, 0)
        XCTAssertTrue(audit.summary.enabled)
    }

    func testAggregateOutputContainsNoHostIPOrCredentials() throws {
        let rule = try policy(["super-private.example.com"])
        var audit = Smart4DryRunAudit(optedIn: true)
        audit.observe(policy: rule, host: "super-private.example.com",
                      resolvedIP: "198.51.100.47", smart3: .confirmedDirect)
        let description = String(describing: audit.summary)
        for sensitive in ["super-private", "example.com", "198.51.100.47",
                          "password", "username", "URL"] {
            XCTAssertFalse(description.contains(sensitive))
        }
        XCTAssertEqual(audit.summary.confirmedMatches, 1)
    }
}
