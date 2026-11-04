import XCTest

/// Disposable signed iPhone Simulator only; exercises display and navigation,
/// never changes network routing, saved profiles or the user's real iPhone.
final class Localization020ReadOnlyUITests: XCTestCase {
    private func record(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = "APL 0.2 locale " + name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Regression: the previous large, long website-exclusions title was
    /// visibly cut off in French and Amharic on a standard iPhone.
    func testShortExclusionsTitleIsVisibleInLongLanguages() {
        for (code, expected) in [("fr", "Exclusions"), ("am", "ልዩ ማለፊያዎች")] {
            let app = XCUIApplication()
            app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                    "-setupGuideSeen.v1", "YES",
                                    "-appLanguage.v1", code,
                                    "-aplSettingsLocaleQA"]
            app.launch()
            let exclusions = app.buttons["settings.siteExclusions"]
            XCTAssertTrue(exclusions.waitForExistence(timeout: 20))
            exclusions.tap()
            let navigationTitle = app.navigationBars.staticTexts[expected]
            XCTAssertTrue(navigationTitle.waitForExistence(timeout: 10),
                          "Short exclusions title for \(code)")
            record(app, "\(code) short-exclusions-header")
            app.terminate()
        }
    }

    func testRepresentativeNewCopyInSettingsImportAndSiteExclusions() {
        let languages = ["en", "fr", "de", "ar", "he", "hi", "ja", "zh-Hant", "am", "ha"]
        for code in languages {
            let app = XCUIApplication()
            app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                    "-setupGuideSeen.v1", "YES",
                                    "-appLanguage.v1", code,
                                    "-aplSettingsLocaleQA"]
            app.launch()

            let language = app.descendants(matching: .any)
                .matching(identifier: "settings.language").firstMatch
            XCTAssertTrue(language.waitForExistence(timeout: 15), "Settings language for \(code)")
            let shortcuts = app.buttons["settings.quickActions"]
            XCTAssertTrue(shortcuts.waitForExistence(timeout: 8), "Shortcuts for \(code)")
            record(app, "\(code) settings")

            let exclusions = app.buttons["settings.siteExclusions"]
            XCTAssertTrue(exclusions.exists, "Site exclusions for \(code)")
            exclusions.tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 9),
                          "Exclusions navigation for \(code)")
            record(app, "\(code) exclusions")
            app.terminate()

            let profilesApp = XCUIApplication()
            profilesApp.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                           "-setupGuideSeen.v1", "YES",
                                           "-appLanguage.v1", code]
            profilesApp.launch()
            let profiles = profilesApp.tabBars.buttons.element(boundBy: 1)
            XCTAssertTrue(profiles.waitForExistence(timeout: 12), "Profiles tab for \(code)")
            profiles.tap()
            let importAction = profilesApp.buttons["profiles.import"]
            XCTAssertTrue(importAction.waitForExistence(timeout: 9), "Import for \(code)")
            importAction.tap()
            XCTAssertTrue(profilesApp.textViews.firstMatch.waitForExistence(timeout: 9),
                          "Proxy import editor for \(code)")
            record(profilesApp, "\(code) proxy-import")
            profilesApp.terminate()
        }
    }
}
