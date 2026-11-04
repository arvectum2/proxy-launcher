import XCTest

/// Read-only a11y acceptance on the disposable Simulator with system font
/// category set to Accessibility XXL by the test runner. No VPN or profiles.
final class AccessibilityLargeTextUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Accessibility XXL - " + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLargeTextSettingsAndActivityAreReachableInLTRAndRTL() {
        for lang in ["de", "ar"] {
            let app = XCUIApplication()
            app.launchArguments += ["-setupGuideSeen.v1", "YES",
                                    "-privacyDisclosureAccepted.v1", "YES",
                                    "-appLanguage.v1", lang,
                                    "-aplHomeProfileQA",
                                    "-aplSettingsLocaleQA"]
            app.launch()
            let settings = app.tabBars.buttons.element(boundBy: 3)
            XCTAssertTrue(settings.waitForExistence(timeout: 20), "Settings tab: \(lang)")
            let theme = app.descendants(matching: .any)
                .matching(identifier: "settings.theme").firstMatch
            XCTAssertTrue(theme.waitForExistence(timeout: 10), "Theme picker: \(lang)")
            let language = app.descendants(matching: .any)
                .matching(identifier: "settings.language").firstMatch
            XCTAssertTrue(language.exists, "Language picker: \(lang)")
            capture(app, "\(lang) settings top")
            let routing = app.descendants(matching: .any)
                .matching(identifier: "settings.returnToPrimary").firstMatch
            XCTAssertTrue(routing.exists, "Auto primary return toggle: \(lang)")
            if !routing.isHittable {
                app.swipeUp()
                app.swipeUp()
            }
            XCTAssertTrue(routing.isHittable,
                          "Primary toggle must be reachable by scrolling: \(lang)")
            capture(app, "\(lang) settings bottom")
            let exclusions = app.buttons["settings.siteExclusions"]
            XCTAssertTrue(exclusions.exists, "Site exclusions: \(lang)")
            if !exclusions.isHittable { app.swipeDown() }
            XCTAssertTrue(exclusions.isHittable, "Exclusions reachable: \(lang)")
            XCTAssertGreaterThanOrEqual(exclusions.frame.height, 44,
                                        "Tap target at Accessibility XXL: \(lang)")
            let activity = app.tabBars.buttons.element(boundBy: 2)
            activity.tap()
            let refresh = app.buttons["activity.refresh"]
            XCTAssertTrue(refresh.waitForExistence(timeout: 10),
                          "Activity refresh is accessible: \(lang)")
            XCTAssertTrue(refresh.isHittable, "Activity refresh is tappable: \(lang)")
            XCTAssertGreaterThanOrEqual(refresh.frame.width, 44)
            XCTAssertGreaterThanOrEqual(refresh.frame.height, 44)
            capture(app, "\(lang) activity")
            app.terminate()
        }
    }
}
