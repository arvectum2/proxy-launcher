import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class SharedIPRouteGuardTests: XCTestCase {
    func testDistinctDependentDomainsRemainDirectWithNoKnownCollision() {
        let result = SharedIPRouteGuard.plan(
            approved: ["example.test": ["203.0.113.10"],
                       "api.example.test": ["203.0.113.11"],
                       "static.example.test": ["203.0.113.12"]],
            nonApproved: ["analytics.example.test": ["203.0.113.99"]]
        )
        XCTAssertEqual(result.allowedAddresses, ["203.0.113.10", "203.0.113.11", "203.0.113.12"])
        XCTAssertTrue(result.dnsBypass.contains("api.example.test=203.0.113.11"))
        XCTAssertTrue(result.withheldAddresses.isEmpty)
    }

    func testUnapprovedHostOnSameCDNAddressBlocksDirectForBothIPv4AndIPv6() {
        let shared4 = "203.0.113.42"
        let shared6 = "2001:db8::42"
        let result = SharedIPRouteGuard.plan(
            approved: ["approved.example.test": [shared4, shared6]],
            nonApproved: ["unapproved.example.test": [shared4, shared6]]
        )
        XCTAssertEqual(Set(result.withheldAddresses), Set([shared4, shared6]))
        XCTAssertEqual(result.blockedHosts, ["approved.example.test"])
        XCTAssertTrue(result.allowedAddresses.isEmpty)
        XCTAssertTrue(result.dnsBypass.isEmpty)
    }

    func testUnresolvedKnownRejectedHostCannotBeProvenSafe() {
        let result = SharedIPRouteGuard.plan(
            approved: ["approved.example.test": ["203.0.113.5"]],
            nonApproved: ["rejected.example.test": nil]
        )
        XCTAssertEqual(result.withheldAddresses, ["203.0.113.5"])
        XCTAssertEqual(result.blockedHosts, ["approved.example.test"])
    }

    func testAmbiguousOneOfSeveralAddressesBlocksWholeDomainMapping() {
        let result = SharedIPRouteGuard.plan(
            approved: ["approved.example.test": ["203.0.113.1", "203.0.113.2"],
                       "safe.example.test": ["203.0.113.3"]],
            nonApproved: ["rejected.example.test": ["203.0.113.2"]]
        )
        XCTAssertEqual(result.allowedAddresses, ["203.0.113.3"])
        XCTAssertEqual(result.dnsBypass, ["safe.example.test=203.0.113.3"])
        XCTAssertEqual(result.withheldAddresses, ["203.0.113.2"])
        XCTAssertEqual(result.blockedHosts, ["approved.example.test"])
    }

    func testIPv6CanonicalizationPreventsFalseNonCollision() {
        let result = SharedIPRouteGuard.plan(
            approved: ["cdn.site.test": ["2001:0DB8:0000:0000:0000:0000:0000:0042"]],
            nonApproved: ["unapproved.site.test": ["2001:db8::42"]]
        )
        XCTAssertEqual(result.withheldAddresses, ["2001:db8::42"])
        XCTAssertTrue(result.allowedAddresses.isEmpty)
        XCTAssertTrue(result.dnsBypass.isEmpty)
    }

    func testSharedIPAfterGraphApprovalAndRejectionCannotEnableDirectRoute() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var graph = SmartExclusionGraph()
        try graph.observe(parent: "site.test", html: ["api.site.test", "tracking.site.test"],
                          network: ["api.site.test", "tracking.site.test"], at: now)
        try graph.set(.approved, parent: "site.test", child: "api.site.test")
        try graph.set(.rejected, parent: "site.test", child: "tracking.site.test")
        XCTAssertEqual(try graph.effective(manual: ["site.test"], at: now),
                       ["api.site.test", "site.test"])
        let result = SharedIPRouteGuard.plan(
            approved: ["api.site.test": ["203.0.113.22"],
                       "site.test": ["203.0.113.21"]],
            nonApproved: ["tracking.site.test": ["203.0.113.22"]]
        )
        XCTAssertEqual(result.allowedAddresses, ["203.0.113.21"])
        XCTAssertEqual(result.dnsBypass, ["site.test=203.0.113.21"])
        XCTAssertEqual(result.blockedHosts, ["api.site.test"])
        XCTAssertEqual(result.withheldAddresses, ["203.0.113.22"])
    }

    func testLiteralIPWithoutKnownConflictsStillHasExplicitUserMeaning() {
        let result = SharedIPRouteGuard.plan(
            approved: ["192.0.2.11": ["192.0.2.11"]], nonApproved: [:]
        )
        XCTAssertEqual(result.allowedAddresses, ["192.0.2.11"])
        XCTAssertEqual(result.dnsBypass, ["192.0.2.11=192.0.2.11"])
        // The resulting NE route is IP-wide; users explicitly entering an IP
        // accept routing for that whole IP and all services on it.
    }
}
