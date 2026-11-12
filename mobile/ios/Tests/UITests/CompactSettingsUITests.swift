import XCTest

/// Focused simulator UI check using a debug-only fake profile label;
/// it never mutates VPN, Keychain, or real profiles.
final class CompactSettingsUITests: XCTestCase {
    func testThemeSegmentsRelocalizeWithoutRestartingAppOrChangingAppearance() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-privacyDisclosureAccepted.v1", "YES",
            "-setupGuideSeen.v1", "YES",
            // Do NOT force "-appLanguage.v1 ru" via process arguments:
            // NSArgumentDomain would mask @AppStorage writes during the test.
            "-aplHomeProfileQA"
        ]
        app.launch()
        let settingsTab = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 20))
        settingsTab.tap()

        let language = app.descendants(matching: .any)
            .matching(identifier: "settings.language").firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 10))
        language.tap()
        let russianFirst = app.buttons["Русский"]
        XCTAssertTrue(russianFirst.waitForExistence(timeout: 8))
        russianFirst.tap()

        let theme = app.descendants(matching: .any)
            .matching(identifier: "settings.theme").firstMatch
        XCTAssertTrue(theme.waitForExistence(timeout: 10))
        XCTAssertTrue(theme.buttons["Системная"].exists)
        XCTAssertTrue(theme.buttons["Светлая"].exists)
        XCTAssertTrue(theme.buttons["Тёмная"].exists)

        language.tap()
        let english = app.buttons["English"]
        XCTAssertTrue(english.waitForExistence(timeout: 8))
        english.tap()
        XCTAssertTrue(theme.buttons["System"].waitForExistence(timeout: 10))
        XCTAssertTrue(theme.buttons["Light"].exists)
        XCTAssertTrue(theme.buttons["Dark"].exists)
        XCTAssertFalse(theme.buttons["Системная"].exists)
        XCTAssertTrue(theme.buttons["System"].isSelected,
                      "The selected theme must survive an in-place locale switch")

        language.tap()
        let russian = app.buttons["Русский"]
        XCTAssertTrue(russian.waitForExistence(timeout: 8))
        russian.tap()
        XCTAssertTrue(theme.buttons["Системная"].waitForExistence(timeout: 10))
        XCTAssertTrue(theme.buttons["Светлая"].exists)
        XCTAssertTrue(theme.buttons["Тёмная"].exists)
        XCTAssertTrue(theme.buttons["Системная"].isSelected)
    }

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
