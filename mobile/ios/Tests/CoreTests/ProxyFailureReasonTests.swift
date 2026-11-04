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

    func testExactErrorCodesAreStable() {
        XCTAssertEqual(ProxyFailureReason.authentication.code, "AUTH")
        XCTAssertEqual(ProxyFailureReason.http407.code, "HTTP 407")
        XCTAssertEqual(ProxyFailureReason.dns.code, "DNS")
        XCTAssertEqual(ProxyFailureReason.tunnel.code, "VPN")
    }

    func testSafeConnectionAlertUsesExistingLocalizedHelpKeys() {
        let dns = NSError(domain: NSURLErrorDomain, code: NSURLErrorDNSLookupFailed,
                          userInfo: [NSLocalizedDescriptionKey: "secret.example:1234"])
        let dnsAdvice = SafeConnectionAlert.forError(dns)
        XCTAssertEqual(dnsAdvice.code, "DNS")
        XCTAssertEqual(dnsAdvice.localizationKey, "Проверьте адрес и порт прокси")
        let authentication = SafeConnectionAlert.forError(ProxyDiagnosticError(.http407))
        XCTAssertEqual(authentication.code, "HTTP 407")
        XCTAssertEqual(authentication.localizationKey,
                       "Следите за статусом соединения. Если подключение не удалось, проверьте адрес, порт, тип и учётные данные.")
        let known = Set([dnsAdvice.localizationKey, authentication.localizationKey])
        for reason in ProxyFailureReason.allCases {
            XCTAssertTrue(known.contains(reason.connectionHelpLocalizationKey))
        }
    }

    func testSafeConnectionAlertNeverDisplaysUntrustedErrorDetails() {
        let secret = "proxy.internal.example:8000 username=private password=privateSecret"
        let errors: [Error] = [
            NSError(domain: "ArvectumVPN", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: secret]),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                    userInfo: [NSLocalizedDescriptionKey: secret]),
            NSError(domain: "private.upstream", code: 500,
                    userInfo: [NSLocalizedDescriptionKey: secret])
        ]
        for error in errors {
            let advice = SafeConnectionAlert.forError(error)
            XCTAssertFalse(advice.localizationKey.contains(secret))
            XCTAssertFalse(advice.code.contains(secret))
        }
    }

    func testSafeConnectionAlertPreservesOnlyApprovedVPNRepairGuidance() {
        let hints = [
            "iOS отключила конфигурацию VPN и не позволила включить её автоматически. Откройте Настройки → VPN и разрешите Arvectum Proxy Launcher, затем повторите подключение.",
            "Конфигурация VPN была изменена системой. Перезапустите подключение — приложение перечитает и восстановит её.",
            "iOS отклонила конфигурацию Packet Tunnel. Конфигурация была восстановлена, но системе всё ещё не удалось её запустить."
        ]
        for hint in hints {
            let error = NSError(domain: "ArvectumVPN", code: 3,
                                userInfo: [NSLocalizedDescriptionKey: hint])
            let advice = SafeConnectionAlert.forError(error)
            XCTAssertEqual(advice.localizationKey, hint)
            XCTAssertEqual(advice.code, "VPN")
        }
    }
}
