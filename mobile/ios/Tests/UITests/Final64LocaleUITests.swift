import XCTest

/// UI smoke coverage for every source language, including all post-Soviet
/// localizations. Disposable simulator only; does not start VPN or edit profiles.
final class Final64LocaleUITests: XCTestCase {
    private let languages = ["en", "ru", "es", "fr", "de", "it", "pt-BR", "pt-PT", "ja", "ko", "zh-Hans", "zh-Hant", "fa", "nl", "id", "tr", "hi", "ar", "vi", "pl", "th", "ur", "bn", "pa", "ta", "te", "mr", "gu", "kn", "ml", "uz", "ms", "fil", "sw", "ro", "hu", "cs", "sk", "el", "he", "ha", "am", "sv", "da", "fi", "nb", "bg", "sr", "hr", "ca", "or", "sl", "uk", "be", "et", "lv", "lt", "ka", "hy", "az", "kk", "tk", "ky", "tg"]

    private func launch(_ code: String, settings: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-setupGuideSeen.v1", "YES",
                               "-privacyDisclosureAccepted.v1", "YES",
                               "-appLanguage.v1", code,
                               "-aplHomeProfileQA"]
        if settings { app.launchArguments.append("-aplSettingsLocaleQA") }
        app.launch()
        return app
    }

    func testAll64LocalesShowFourReachableTabsAndSettings() {
        XCTAssertEqual(languages.count, 64)
        for (index, code) in languages.enumerated() {
            let app = launch(code)
            let tabs = app.tabBars.buttons
            XCTAssertTrue(tabs.element(boundBy: 0).waitForExistence(timeout: 18),
                          "First tab missing in \(code)")
            XCTAssertEqual(tabs.count, 4, "Navigation tabs in \(code)")
            for i in 0..<4 {
                let tab = tabs.element(boundBy: i)
                XCTAssertTrue(tab.isHittable, "Tab \(i) not hittable in \(code)")
                XCTAssertFalse(tab.label.isEmpty, "Blank tab label in \(code)")
                XCTAssertLessThanOrEqual(tab.label.count, 12,
                        "Too-long tab \(i) in \(code): \(tab.label)")
                XCTAssertGreaterThanOrEqual(tab.frame.minX, -2, "Tab \(i) off left in \(code)")
                XCTAssertLessThanOrEqual(tab.frame.maxX, app.frame.width + 2,
                                         "Tab \(i) off right in \(code)")
            }
            let language = app.descendants(matching: .any)
                .matching(identifier: "settings.language").firstMatch
            XCTAssertTrue(language.waitForExistence(timeout: 12),
                          "Settings language selector missing in \(code)")
            let exclusions = app.buttons["settings.siteExclusions"]
            XCTAssertTrue(exclusions.exists, "Site exclusions missing in \(code)")
            if (index + 1) % 8 == 0 { print("APL64_UIQA_SET \(index+1)/64 PASS \(code)") }
            app.terminate()
        }
    }

    func testNewElevenAndRtlLocaleSecondaryScreens() {
        for code in ["be", "et", "lv", "lt", "ka", "hy", "az", "kk", "tk", "ky", "tg",
                     "ar", "he", "fa", "fr", "de"] {
            let app = launch(code)
            let language = app.descendants(matching: .any)
                .matching(identifier: "settings.language").firstMatch
            XCTAssertTrue(language.waitForExistence(timeout: 18), "Settings in \(code)")
            let header = XCTAttachment(screenshot: app.screenshot())
            header.name = "64 locale: \(code) Settings"
            header.lifetime = .keepAlways
            add(header)

            let exclusions = app.buttons["settings.siteExclusions"]
            XCTAssertTrue(exclusions.exists, "Exclusions in \(code)")
            if !exclusions.isHittable { app.swipeUp() }
            XCTAssertTrue(exclusions.isHittable, "Exclusions not reachable in \(code)")
            exclusions.tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 12),
                          "Site exclusions navigation in \(code)")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "64 locale: \(code) Exclusions"
            shot.lifetime = .keepAlways
            add(shot)
            let close = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 8), "Exclusions dismiss control in \(code)")
            close.tap()
            let profiles = app.tabBars.buttons.element(boundBy: 1)
            XCTAssertTrue(profiles.waitForExistence(timeout: 8), "Profiles tab in \(code)")
            profiles.tap()
            let importButton = app.buttons["profiles.import"]
            XCTAssertTrue(importButton.waitForExistence(timeout: 12), "Import in \(code)")
            importButton.tap()
            XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 12),
                          "Proxy import entry in \(code)")
            let importShot = XCTAttachment(screenshot: app.screenshot())
            importShot.name = "64 locale: \(code) Import"
            importShot.lifetime = .keepAlways
            add(importShot)
            print("APL64_UIQA_DEEP PASS \(code)")
            app.terminate()
        }
    }
    /// The host simulator must use Accessibility XXL content size. The Settings
    /// layout switches from fit-to-screen to scrollable cards; no VPN mutation.
    func testPostSovietElevenXXLSettingsReachable() {
        for code in ["be", "et", "lv", "lt", "ka", "hy", "az", "kk", "tk", "ky", "tg"] {
            let app = launch(code)
            let selected = app.tabBars.buttons.element(boundBy: 3)
            XCTAssertTrue(selected.waitForExistence(timeout: 18), "Settings tab at XXL: \(code)")
            XCTAssertTrue(selected.isHittable, "Settings tab blocked at XXL: \(code)")
            let menu = app.descendants(matching: .any)
                .matching(identifier: "settings.language").firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 12), "Language at XXL: \(code)")
            let theme = app.descendants(matching: .any)
                .matching(identifier: "settings.theme").firstMatch
            XCTAssertTrue(theme.exists, "Theme at XXL: \(code)")
            let top = XCTAttachment(screenshot: app.screenshot())
            top.name = "64 locale XXL \(code) settings top"
            top.lifetime = .keepAlways
            add(top)
            let toggle = app.descendants(matching: .any)
                .matching(identifier: "settings.returnToPrimary").firstMatch
            XCTAssertTrue(toggle.exists, "Return toggle must be in scrollable tree: \(code)")
            for _ in 0..<4 {
                if toggle.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(toggle.isHittable, "Return toggle unreachable at XXL: \(code)")
            let autoExpand = app.switches["settings.autoExpandExclusions"]
            XCTAssertTrue(autoExpand.exists, "Automatic exclusion mode switch missing at XXL: \(code)")
            for _ in 0..<6 {
                if autoExpand.isHittable { break }
                app.swipeDown()
            }
            XCTAssertTrue(autoExpand.isHittable,
                          "Auto expansion switch unreachable at XXL: \(code)")
            let exclusions = app.buttons["settings.siteExclusions"]
            for _ in 0..<4 {
                if exclusions.isHittable { break }
                app.swipeDown()
            }
            XCTAssertTrue(exclusions.isHittable, "Site exclusions unreachable at XXL: \(code)")
            XCTAssertGreaterThanOrEqual(exclusions.frame.height, 44,
                                        "Accessible site exclusions target at XXL: \(code)")
            print("APL64_UIQA_XXL PASS \(code)")
            app.terminate()
        }
    }

}
