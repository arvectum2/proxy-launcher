import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class AdaptiveRouteLearningTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let network = "ephemeral-network-test"
    private func repeated(_ learning: inout AdaptiveRouteLearning, host: String = "auth.example.com") {
        for id in ["a", "b"] {
            _ = learning.proxyFailure(host: host, connectionID: id, type: .proxyTimeout,
                                      proxyHealthy: true, networkID: network, at: start)
        }
    }

    func testLoginRedirectTriggersProbeOnTwoDistinctProxyFailuresNotOne() {
        var l = AdaptiveRouteLearning()
        XCTAssertEqual(l.proxyFailure(host: "auth.example.com", connectionID: "a", type: .proxyTimeout,
            proxyHealthy: true, networkID: network, at: start), .keepProxy)
        XCTAssertEqual(l.proxyFailure(host: "auth.example.com", connectionID: "a", type: .proxyTimeout,
            proxyHealthy: true, networkID: network, at: start), .keepProxy)
        XCTAssertEqual(l.proxyFailure(host: "auth.example.com", connectionID: "b", type: .proxyRefused,
            proxyHealthy: true, networkID: network, at: start.addingTimeInterval(2)), .verifyDirect("auth.example.com"))
        XCTAssertTrue(l.directHosts(networkID: network, exactHostTransport: true, at: start).isEmpty)
        XCTAssertEqual(l.comparison(host: "auth.example.com", proxyFailed: true, directSucceeded: true,
            independentlyDirect: true, exactHostTransport: false, networkID: network,
            at: start.addingTimeInterval(3)), .unsupportedDirect("auth.example.com"))
        XCTAssertTrue(l.directHosts(networkID: network, exactHostTransport: false, at: start).isEmpty)
    }

    func testDiagnosisIsThrottledToOneProbePerMinutePerHost() {
        var l = AdaptiveRouteLearning()
        XCTAssertEqual(l.proxyFailure(host: "auth.example.com", connectionID: "a",
            type: .proxyTimeout, proxyHealthy: true, networkID: network, at: start), .keepProxy)
        XCTAssertEqual(l.proxyFailure(host: "auth.example.com", connectionID: "b",
            type: .proxyTimeout, proxyHealthy: true, networkID: network,
            at: start.addingTimeInterval(1)), .verifyDirect("auth.example.com"))
        XCTAssertEqual(l.proxyFailure(host: "auth.example.com", connectionID: "c",
            type: .proxyTimeout, proxyHealthy: true, networkID: network,
            at: start.addingTimeInterval(2)), .keepProxy)
        XCTAssertEqual(l.proxyFailure(host: "auth.example.com", connectionID: "d",
            type: .proxyTimeout, proxyHealthy: true, networkID: network,
            at: start.addingTimeInterval(61)), .verifyDirect("auth.example.com"))
    }

    func testApprovedIndependentEvidenceLearnsFor24HoursAndReverts() {
        var l = AdaptiveRouteLearning(); repeated(&l)
        XCTAssertEqual(l.comparison(host: "auth.example.com", proxyFailed: true, directSucceeded: true,
            independentlyDirect: true, exactHostTransport: true, networkID: network,
            at: start.addingTimeInterval(2)), .verifyDirect("auth.example.com"))
        XCTAssertEqual(l.comparison(host: "auth.example.com", proxyFailed: true, directSucceeded: true,
            independentlyDirect: true, exactHostTransport: true, networkID: network,
            at: start.addingTimeInterval(3)), .temporaryDirect("auth.example.com"))
        XCTAssertEqual(l.directHosts(networkID: network, exactHostTransport: true, at: start.addingTimeInterval(4)), ["auth.example.com"])
        XCTAssertEqual(l.directHosts(networkID: "new-network", exactHostTransport: true, at: start), [])
        XCTAssertEqual(l.directHosts(networkID: network, exactHostTransport: true, at: start.addingTimeInterval(86405)), [])
        XCTAssertEqual(l.directFailure("auth.example.com"), .revert("auth.example.com"))
        XCTAssertTrue(l.directHosts(networkID: network, exactHostTransport: true, at: start).isEmpty)
    }

    func testNoAutoBypassForOfflineTLSApplicationErrorsOrFakeProbe() {
        var l = AdaptiveRouteLearning()
        for failure: AdaptiveRouteLearning.Failure in [.proxyAuthentication, .tlsApplication, .pageTimeout, .offline] {
            XCTAssertEqual(l.proxyFailure(host: "auth.example.com", connectionID: "x", type: failure,
                proxyHealthy: true, networkID: network, at: start), .keepProxy)
        }
        XCTAssertEqual(l.proxyFailure(host: "auth.example.com", connectionID: "x", type: .proxyTimeout,
            proxyHealthy: false, networkID: network, at: start), .keepProxy)
        repeated(&l)
        XCTAssertEqual(l.comparison(host: "auth.example.com", proxyFailed: true, directSucceeded: true,
            independentlyDirect: false, exactHostTransport: true, networkID: network, at: start), .keepProxy)
    }

    func testDifferentHostAndTrackingHostCannotInheritLearnedRoute() {
        var l = AdaptiveRouteLearning(); repeated(&l)
        XCTAssertEqual(l.comparison(host: "tracker.other.test", proxyFailed: true, directSucceeded: true,
            independentlyDirect: true, exactHostTransport: true, networkID: network, at: start), .keepProxy)
        XCTAssertEqual(l.proxyFailure(host: "analytics.example.com", connectionID: "x", type: .proxyTimeout,
            proxyHealthy: true, networkID: network, at: start), .keepProxy)
        l.reject("auth.example.com")
        XCTAssertEqual(l.proxyFailure(host: "auth.example.com", connectionID: "c", type: .proxyTimeout,
            proxyHealthy: true, networkID: network, at: start), .keepProxy)
        XCTAssertTrue(l.directHosts(networkID: network, exactHostTransport: true, at: start).isEmpty)
    }

    func testBoundedSerializableAndResetOnNetworkChange() throws {
        var l = AdaptiveRouteLearning(); repeated(&l)
        let data = try JSONEncoder().encode(l)
        var copy = try JSONDecoder().decode(AdaptiveRouteLearning.self, from: data)
        XCTAssertEqual(copy, l)
        copy.prune(at: start.addingTimeInterval(1), networkID: "new-network")
        XCTAssertTrue(copy.hosts.isEmpty)
    }
}
