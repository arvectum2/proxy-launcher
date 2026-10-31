import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class ProxyFailureReasonTests: XCTestCase {
    func testClassifiesKnownURLErrors() {
        let examples: [(Int, ProxyFailureReason)] = [
            (NSURLErrorNotConnectedToInternet, .offline),
            (NSURLErrorDNSLookupFailed, .dns),
            (NSURLErrorCannotConnectToHost, .tcp),
            (NSURLErrorSecureConnectionFailed, .tls),
            (NSURLErrorTimedOut, .timeout),
        ]
        for (code, expected) in examples {
            XCTAssertEqual(ProxyFailureReason.classify(NSError(domain: NSURLErrorDomain, code: code)), expected)
        }
    }

    func testClassifiesPOSIXAndVPN() {
        XCTAssertEqual(ProxyFailureReason.classify(NSError(domain: NSPOSIXErrorDomain, code: 61)), .tcp)
        XCTAssertEqual(ProxyFailureReason.classify(NSError(domain: NSPOSIXErrorDomain, code: 51)), .offline)
        XCTAssertEqual(ProxyFailureReason.classify(NSError(domain: "ArvectumVPN", code: 2)), .tunnel)
    }

    func testUnknownErrorsFailClosedWithoutLeakingDetails() {
        let secret = "passwordSecret:private-server.example"
        let arbitrary = NSError(domain: "random", code: 938, userInfo: [NSLocalizedDescriptionKey: secret])
        let reason = ProxyFailureReason.classify(arbitrary)
        XCTAssertEqual(reason, .unknown)
        XCTAssertFalse(reason.code.contains(secret))
        XCTAssertFalse(ProxyDiagnosticError(reason).localizedDescription.contains(secret))
    }

    func testNestedReasonAndPriority() {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        let wrapping = NSError(domain: "wrapper", code: 1, userInfo: [NSUnderlyingErrorKey: underlying])
        XCTAssertEqual(ProxyFailureReason.classify(wrapping), .dns)
        XCTAssertEqual(ProxyFailureReason.mostRelevant([.protocolMismatch, .authentication, .timeout]), .authentication)
        XCTAssertEqual(ProxyFailureReason.mostRelevant([]), .unknown)
    }

    func testHTTP407NeverReportsSuccessIncludingDigestChallenges() {
        XCTAssertNil(ProxyFailureReason.forHTTPConnectStatus(200))
        XCTAssertNil(ProxyFailureReason.forHTTPConnectStatus(204))
        XCTAssertEqual(ProxyFailureReason.forHTTPConnectStatus(407), .http407)
        XCTAssertEqual(ProxyFailureReason.forHTTPConnectStatus(403), .rejected)
        XCTAssertEqual(ProxyFailureReason.forHTTPConnectStatus(502), .rejected)
    }

    func testExactErrorCodesAreStable() {
        XCTAssertEqual(ProxyFailureReason.authentication.code, "AUTH")
        XCTAssertEqual(ProxyFailureReason.http407.code, "HTTP 407")
        XCTAssertEqual(ProxyFailureReason.dns.code, "DNS")
        XCTAssertEqual(ProxyFailureReason.tunnel.code, "VPN")
    }
}
