import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class SiteExclusionSaveFailureTests: XCTestCase {
    func testAllManualInputErrorsMapToSafeFiniteReasons() {
        let cases: [(SiteExclusionError, SiteExclusionSaveFailure)] = [
            (.malformedIPv6, .invalidAddress),
            (.unsupportedMask, .maskUnsupported),
            (.whitespace, .invalidAddress),
            (.malformed, .invalidAddress),
            (.tooLong, .invalidAddress),
            (.tooMany, .tooManyManual)
        ]
        for (error, expected) in cases {
            XCTAssertEqual(SiteExclusionSaveFailure.classify(error), expected)
        }
    }

    func testAllGraphErrorsMapToExistingLocalizedKeys() {
        let cases: [(SmartGraphError, String)] = [
            (.invalidParent, "Некорректный домен сайта"),
            (.invalidChild, "Связанный домен не принадлежит сайту"),
            (.tooMany, "Превышен безопасный предел связанных доменов")
        ]
        for (error, key) in cases {
            XCTAssertEqual(SiteExclusionSaveFailure.classify(error).translatedGraphKey, key)
        }
    }

    func testUntrustedStorageDetailsNeverEnterFallbacks() {
        let secret = "pass123@private-proxy.example.invalid"
        let error = NSError(domain: "storage", code: 911,
                            userInfo: [NSLocalizedDescriptionKey: "Failed: \(secret)"])
        let result = SiteExclusionSaveFailure.classify(error)
        XCTAssertEqual(result, .unknown)
        XCTAssertNil(result.translatedGraphKey)
        XCTAssertFalse(result.russianFallback.contains(secret))
        XCTAssertFalse(result.englishFallback.contains(secret))
        XCTAssertFalse(result.englishFallback.contains("Failed"))
    }

    func testBoundedMessagesNeverContainUserInput() {
        let allErrors: [Error] = [
            SiteExclusionError.tooMany,
            SiteExclusionError.unsupportedMask,
            SiteExclusionError.malformed,
            SmartGraphError.invalidParent,
            SmartGraphError.invalidChild,
            SmartGraphError.tooMany,
            NSError(domain: "unexpected", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "proxy://secret@hidden.example"])
        ]
        for error in allErrors {
            let reason = SiteExclusionSaveFailure.classify(error)
            XCTAssertFalse(reason.russianFallback.isEmpty)
            XCTAssertFalse(reason.englishFallback.isEmpty)
            XCTAssertFalse(reason.englishFallback.contains("proxy://"))
            XCTAssertFalse(reason.russianFallback.contains("proxy://"))
        }
    }

    func testNoChangeToExistingNormalizerOrExclusionGraphBehavior() throws {
        let normalized = try SiteExclusionPolicy.normalizeAll(["EXAMPLE.com", "www.example.com"])
        XCTAssertEqual(normalized, ["example.com", "www.example.com"])
        XCTAssertThrowsError(try SiteExclusionPolicy.normalizeAll(["*.example.com"]))
    }
}
