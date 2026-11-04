import XCTest

/// Explicit ad demo-only hardware QA; NEVER sends production RSYA traffic.
/// This is not an advertising fill-rate guarantee for the App Store binary.
final class RSYABannerPhysicalUITests: XCTestCase {
    func testDemoRSYABannerLoadedAndRenderedOnRealIPhone() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone ad renderer required")
#else
        guard ProcessInfo.processInfo.environment["APL_ADS_DEMO_DEVICE_QA"] == "enabled" else {
            throw XCTSkip("Demo ad QA opt-in only")
        }
        let app = XCUIApplication()
        app.launchArguments += [
            "-privacyDisclosureAccepted.v1", "YES",
            "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru",
            "-APL_ENABLE_DEMO_BANNER"
        ]
        app.launch()
        let home = app.tabBars.buttons["Домой"]
        XCTAssertTrue(home.waitForExistence(timeout: 12), "Home was not displayed")
        // The primary banner ONLY exposes this label when the real SDK
        // returns a creative (not when a placeholder or mock is displayed).
        let bannerLabel = app.staticTexts["Реклама"].firstMatch
        XCTAssertTrue(bannerLabel.waitForExistence(timeout: 28),
                      "Yandex demo banner did not load a real SDK creative")
        XCTAssertTrue(app.buttons["Подключиться"].firstMatch.exists,
                      "Ad placement obscured the main Connect button")
        print("APL_DEMO_RSYA_REAL_SDK_BANNER_RENDERED_ON_IPHONE")
#endif
    }
}
