import XCTest

/// Navigation-only device review. Does not start VPN, edit user profiles,
/// change routing, touch Keychain, or exercise ad clicks.
final class UXReadOnlyNavigationUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "UX 0.2 - " + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testReviewPrimaryScreensAndSecondaryToolsWithoutChanges() {
        let app = XCUIApplication()
        app.launchArguments += ["-setupGuideSeen.v1", "YES",
                                "-privacyDisclosureAccepted.v1", "YES",
                                "-appLanguage.v1", "ru"]
        app.launch()

        let home = app.tabBars.buttons["Домой"]
        XCTAssertTrue(home.waitForExistence(timeout: 25), "Home tab")
        XCTAssertTrue(app.buttons["Подключиться"].waitForExistence(timeout: 15)
                      || app.buttons["Отключить"].exists
                      || app.buttons["Добавить прокси"].exists,
                      "Primary VPN or initial setup action must be visible")
        capture(app, "Home")

        let profiles = app.tabBars.buttons["Профили"]
        XCTAssertTrue(profiles.exists)
        profiles.tap()
        XCTAssertTrue(app.buttons["profiles.import"].waitForExistence(timeout: 12))
        capture(app, "Profiles")

        app.buttons["profiles.import"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 12))
        capture(app, "Import")
        app.buttons["Закрыть"].tap()

        app.buttons["profiles.encryptedBackup"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 12))
        capture(app, "Encrypted backup")
        app.buttons["Закрыть"].tap()

        let activity = app.tabBars.buttons["Активность"]
        XCTAssertTrue(activity.exists)
        activity.tap()
        capture(app, "Activity")

        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.exists)
        settings.tap()
        let language = app.descendants(matching: .any)
            .matching(identifier: "settings.language").firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 12))
        capture(app, "Settings")

        app.buttons["Исключения сайтов"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 12))
        capture(app, "Site exclusions")
    }
}
