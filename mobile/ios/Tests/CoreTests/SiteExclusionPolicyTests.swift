import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class SiteExclusionPolicyTests: XCTestCase {
    func testNormalizesURLAndHostPort() throws {
        XCTAssertEqual(try SiteExclusionPolicy.normalize("HTTPS://Example.COM/path"), "example.com")
        XCTAssertEqual(try SiteExclusionPolicy.normalize("example.com:443"), "example.com")
        XCTAssertEqual(try SiteExclusionPolicy.normalize(" [2001:db8::1]:443 "), "2001:db8::1")
    }

    func testRejectsMasks() {
        XCTAssertThrowsError(try SiteExclusionPolicy.normalize("*.example.com")) { error in
            XCTAssertEqual(error as? SiteExclusionError, .unsupportedMask)
        }
    }

    func testDeduplicatesAndSorts() throws {
        XCTAssertEqual(try SiteExclusionPolicy.normalizeAll(["B.example", "a.example", "b.example"]), ["a.example", "b.example"])
    }
}
