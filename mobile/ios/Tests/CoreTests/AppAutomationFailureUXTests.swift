import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class AppAutomationFailureUXTests: XCTestCase {
    private let secret = "proxy-user:secret-password@internal.example.invalid:8543/private"

    func testStorageMessageUsesFixedTranslatedKeysAndNoExternalException() {
        let message = AppAutomationFailureUX.storage { "L(\($0))" }
        XCTAssertEqual(message, "L(Сохранить) · STORE\nL(Недоступен)")
        XCTAssertFalse(message.contains(secret))
    }

    func testKnownNestedNSErrorUsesOnlySafeFiniteReasonCode() {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorDNSLookupFailed,
                                 userInfo: [NSLocalizedDescriptionKey: secret,
                                            NSURLErrorFailingURLStringErrorKey: "https://\(secret)"])
        let wrapped = NSError(domain: "opaque.private.domain", code: 319,
                              userInfo: [NSLocalizedDescriptionKey: "private: \(secret)",
                                         NSUnderlyingErrorKey: underlying])
        let message = AppAutomationFailureUX.vpn(wrapped) { "L(\($0))" }
        XCTAssertEqual(message, "L(Настройки) · DNS\nL(Недоступен)")
        XCTAssertFalse(message.contains(secret))
        XCTAssertFalse(message.contains("opaque.private.domain"))
        XCTAssertFalse(message.contains("private:"))
    }

    func testUnknownNSErrorCannotLeakHostPathOrCredential() {
        let raw = NSError(domain: "com.provider.secure-store", code: 402,
                          userInfo: [NSLocalizedDescriptionKey: secret,
                                     NSFilePathErrorKey: "/var/mobile/private/\(secret)"])
        XCTAssertEqual(AppAutomationFailureUX.vpn(raw, translate: { $0 }),
                       "Настройки · VPN\nНедоступен")
    }

    func testKnownPlatformFailuresStayTypedAndNeverIncludeUntrustedDetails() {
        let examples = [(NSURLErrorNotConnectedToInternet, "NET"),
                        (NSURLErrorTimedOut, "TIMEOUT"),
                        (NSURLErrorCannotConnectToHost, "TCP")]
        for (code, safeCode) in examples {
            let error = NSError(domain: NSURLErrorDomain, code: code,
                                userInfo: [NSLocalizedDescriptionKey: secret])
            let message = AppAutomationFailureUX.vpn(error) { $0 }
            XCTAssertTrue(message.contains(" · \(safeCode)\n"))
            XCTAssertFalse(message.contains(secret))
        }
    }
}
