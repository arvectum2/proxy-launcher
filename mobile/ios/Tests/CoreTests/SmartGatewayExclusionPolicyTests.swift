import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class SmartGatewayExclusionPolicyTests: XCTestCase {
    func testManualRootApprovedDependencyAndApexWWWButNotThirdParty() {
        let result = SmartGatewayExclusionPolicy.approvedHosts(from: [
            "gosuslugi.ru", "api.gosuslugi.ru", "tracker.third-party.test"
        ])
        XCTAssertTrue(result.contains("gosuslugi.ru"))
        XCTAssertTrue(result.contains("www.gosuslugi.ru"))
        XCTAssertTrue(result.contains("gu-st.ru"))
        XCTAssertTrue(result.contains("api.gosuslugi.ru"))
        XCTAssertFalse(result.contains("unknown.gosuslugi.ru"))
        XCTAssertFalse(result.contains("analytics.other.test"))
    }

    func testNeverSendsLiteralIPv4IPv6WildcardOrDuplicates() {
        let result = SmartGatewayExclusionPolicy.approvedHosts(from: [
            "192.0.2.17", "2001:db8::42", "example.com", "example.com"
        ])
        XCTAssertEqual(result, ["example.com", "www.example.com"])
    }
}
