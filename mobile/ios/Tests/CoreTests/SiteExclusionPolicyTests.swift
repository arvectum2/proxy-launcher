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

    func testExclusionPairsBareDomainWithWWWInBothDirections() {
        XCTAssertEqual(
            SiteExclusionPolicy.routingHosts(for: "gosuslugi.ru"),
            ["gosuslugi.ru", "www.gosuslugi.ru"]
        )
        XCTAssertEqual(
            SiteExclusionPolicy.routingHosts(for: "www.gosuslugi.ru"),
            ["gosuslugi.ru", "www.gosuslugi.ru"]
        )
        XCTAssertEqual(
            SiteExclusionPolicy.routingHosts(for: "zakupki.gov.ru"),
            ["www.zakupki.gov.ru", "zakupki.gov.ru"].sorted()
        )
    }

    func testLiteralIPExclusionsAreNeverExpanded() {
        XCTAssertEqual(SiteExclusionPolicy.routingHosts(for: "192.0.2.77"), ["192.0.2.77"])
        XCTAssertEqual(SiteExclusionPolicy.routingHosts(for: "2001:db8::1"), ["2001:db8::1"])
        XCTAssertEqual(SiteExclusionPolicy.routingHosts(for: "127.0.0.1"), ["127.0.0.1"])
    }

    func testOtherSubdomainsAreNotAccidentallyIncluded() {
        let resolved = SiteExclusionPolicy.routingHosts(for: "gosuslugi.ru")
        XCTAssertFalse(resolved.contains("lk.gosuslugi.ru"))
        XCTAssertFalse(resolved.contains("www2.gosuslugi.ru"))
    }

    func testDeduplicatesAndSorts() throws {
        XCTAssertEqual(try SiteExclusionPolicy.normalizeAll(["B.example", "a.example", "b.example"]), ["a.example", "b.example"])
    }
}
