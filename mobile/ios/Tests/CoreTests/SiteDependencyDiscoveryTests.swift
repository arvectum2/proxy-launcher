import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class SiteDependencyDiscoveryTests: XCTestCase {
    func testFindsFirstPartyResourcesButNotThirdParty() {
        let html = #"<script src="https://lk.gosuslugi.ru/app.js"></script><link href='//www.gosuslugi.ru/main.css'><img src="https://tracker.example.net/pixel"><a href="https://evilgosuslugi.ru/">"#
        XCTAssertEqual(SiteDependencyDiscovery.candidates(html: html, for: "gosuslugi.ru"), ["lk.gosuslugi.ru", "www.gosuslugi.ru"])
    }
    func testRejectsSimilarDomainAndMalformedHost() {
        let html = #"<img src="https://a.example.com/a"><img src="https://badexample.com/b"><img src="https://foo.example.com:443/c">"#
        XCTAssertEqual(SiteDependencyDiscovery.candidates(html: html, for: "example.com"), ["a.example.com"])
    }
    func testNoImplicitCrossSiteExclusions() {
        XCTAssertEqual(SiteDependencyDiscovery.candidates(html: #"<script src="https://gu-st.ru/a.js">"#, for: "gosuslugi.ru"), [])
    }
    func testRuntimeRequestsFindDynamicResourcesAndRejectThirdParty() {
        let urls = ["https://api.example.com/v1", "https://cdn.example.com/a.css", "https://tracker.test/x", "https://evil-example.com/x", "file:///tmp/x", "https://api.example.com/v2"]
        XCTAssertEqual(SiteDependencyDiscovery.resourceCandidates(urls: urls, for: "example.com"), ["api.example.com", "cdn.example.com"])
    }
    func testRuntimeCandidatesAreBoundedAndSorted() {
        let urls = (0..<80).map { "https://s\($0).example.com/app.js" }
        let found = SiteDependencyDiscovery.resourceCandidates(urls: urls, for: "example.com")
        XCTAssertEqual(found.count, SiteDependencyDiscovery.maxCandidates)
        XCTAssertEqual(found, found.sorted())
    }
    func testCannotTreatSiblingOrUnrelatedDomainsAsFirstParty() {
        let urls = ["https://example.com.evil.test/x", "https://a-example.com/x", "https://foo.example.com/x", "https://foo.EXAMPLE.com/x"]
        XCTAssertEqual(SiteDependencyDiscovery.resourceCandidates(urls: urls, for: "www.example.com"), ["foo.example.com"])
    }
    func testRuntimeRequestsRejectLookalikeAndInvalidURLs() {
        XCTAssertEqual(SiteDependencyDiscovery.resourceCandidates(urls: ["https://notexample.com/a", "ftp://api.example.com/b", "https://foo.example.com:8443/x"], for: "example.com"), ["foo.example.com"])
    }
}
