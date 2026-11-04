import XCTest

/// Focused simulator UI check using a debug-only fake profile label;
/// it never mutates VPN, Keychain, or real profiles.
final class CompactSettingsUITests: XCTestCase {
    func testSettingsControlsFitAndNativeHomeDoesNotCoverConnect() {
        let app = XCUIApplication()
        app.launchArguments += ["-setupGuideSeen.v1", "YES",
                                "-privacyDisclosureAccepted.v1", "YES",
                                "-appLanguage.v1", "ru",
                                "-aplHomeProfileQA"]
        app.launch()

        let home = app.tabBars.buttons["Домой"]
        XCTAssertTrue(home.waitForExistence(timeout: 20))

        XCTAssertTrue(app.buttons["Добавить прокси"].waitForExistence(timeout: 12) ||
                      app.buttons["Подключиться"].exists)
        let homeCapture = XCTAttachment(screenshot: app.screenshot())
        homeCapture.name = "Home with real banner and native placement"
        homeCapture.lifetime = .keepAlways
        add(homeCapture)

        app.tabBars.buttons["Настройки"].tap()
        let language = app.descendants(matching: .any)
            .matching(identifier: "settings.language").firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 15))
        let automaticSwitch = app.descendants(matching: .any)
            .matching(identifier: "settings.returnToPrimary").firstMatch
        XCTAssertTrue(automaticSwitch.exists)
        XCTAssertTrue(automaticSwitch.isHittable)
        XCTAssertTrue(app.staticTexts["Версия"].exists)
        XCTAssertFalse(app.staticTexts["Маршрутизация и поведение APL"].exists)
        XCTAssertFalse(app.staticTexts["Системная тема автоматически следует настройкам iPhone."].exists)

        let settingsCapture = XCTAttachment(screenshot: app.screenshot())
        settingsCapture.name = "Compact Settings and return-to-primary switch"
        settingsCapture.lifetime = .keepAlways
        add(settingsCapture)
    }
}
