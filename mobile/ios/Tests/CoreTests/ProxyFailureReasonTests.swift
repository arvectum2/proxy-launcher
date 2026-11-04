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

    func testEngineDrainTimeoutIsReportedAsSafeTunnelFailure() {
        let reason = ProxyFailureReason.classify(TunnelEngineDrainError.timeout)
        XCTAssertEqual(reason, .tunnel)
        XCTAssertEqual(reason.code, "VPN")
    }

    func testSafeDisplayNeverRendersNSErrorSecretsOrUnknownRawText() {
        let secret = "auth:secret@private-upstream.invalid"
        let error = NSError(domain: "unknown-provider", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Could not connect to \(secret)",
            NSURLErrorFailingURLStringErrorKey: "https://\(secret)"
        ])
        let display = ProxyFailureReason.safeDisplay(for: error, translate: { $0 })
        XCTAssertEqual(ProxyFailureReason.classify(error), .unknown)
        XCTAssertTrue(display.contains("UNKNOWN"))
        XCTAssertFalse(display.contains(secret))
        XCTAssertFalse(display.contains("Could not connect"))
        XCTAssertFalse(display.contains("https://"))
    }

    func testSafeDisplayHasActionableGuidanceForEveryReason() {
        for reason in ProxyFailureReason.allCases {
            let error = ProxyDiagnosticError(reason)
            let display = ProxyFailureReason.safeDisplay(for: error, translate: { "[\($0)]" })
            XCTAssertTrue(display.contains(reason.code))
            XCTAssertTrue(display.contains("[\(reason.recoveryGuidanceKey)]"))
            XCTAssertFalse(reason.recoveryGuidanceKey.isEmpty)
        }
        XCTAssertEqual(ProxyFailureReason.http407.recoveryGuidanceKey,
                       "Логин и пароль нужны только для прокси с авторизацией.")
        XCTAssertEqual(ProxyFailureReason.protocolMismatch.recoveryGuidanceKey,
                       "Если тип подключения неизвестен, уточните его у поставщика. После заполнения нажмите «Сохранить».")
    }

    func testNestedErrorDisplayUsesTypedReasonOnly() {
        let secret = "sensitive-proxy.local:8080"
        let underlying = NSError(domain: NSURLErrorDomain,
                                 code: NSURLErrorDNSLookupFailed,
                                 userInfo: [NSLocalizedDescriptionKey: secret])
        let wrapping = NSError(domain: "wrapper", code: 1,
                               userInfo: [NSUnderlyingErrorKey: underlying])
        let display = ProxyFailureReason.safeDisplay(for: wrapping, translate: { $0 })
        XCTAssertTrue(display.contains("DNS"))
        XCTAssertFalse(display.contains(secret))
    }

    func testExplicitVPNRecoveryHintsAreSafeAndDoNotRenderRawNSError() {
        let hints: [(ProxyRecoveryHint, String)] = [
            (.vpnDisabled, "Настройки → VPN"),
            (.vpnStale, "Перезапустите подключение"),
            (.vpnInvalid, "Packet Tunnel"),
        ]
        for (hint, expected) in hints {
            let error = ProxyDiagnosticError(.tunnel, recoveryHint: hint)
            let display = ProxyFailureReason.safeDisplay(for: error, translate: { $0 })
            XCTAssertTrue(display.contains("VPN"))
            XCTAssertTrue(display.contains(expected))
            XCTAssertTrue(display.contains(hint.localizationKey))
        }
        let secret = "username:password@private-proxy.invalid"
        let raw = NSError(domain: "ArvectumVPN", code: 999,
                          userInfo: [NSLocalizedDescriptionKey: secret])
        XCTAssertFalse(ProxyFailureReason.safeDisplay(for: raw, translate: { $0 }).contains(secret))
    }

    func testExactErrorCodesAreStable() {
        XCTAssertEqual(ProxyFailureReason.authentication.code, "AUTH")
        XCTAssertEqual(ProxyFailureReason.http407.code, "HTTP 407")
        XCTAssertEqual(ProxyFailureReason.dns.code, "DNS")
        XCTAssertEqual(ProxyFailureReason.tunnel.code, "VPN")
    }
}
