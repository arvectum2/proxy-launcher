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
}
