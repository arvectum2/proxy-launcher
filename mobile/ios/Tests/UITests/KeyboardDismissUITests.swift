import XCTest

/// Upward swipes on content dismiss the keyboard without adding an on-screen
/// accessory button; no stored user proxies, password or VPN state touched.
final class KeyboardDismissUITests: XCTestCase {
    private func swipeUpToDismiss(_ app: XCUIApplication, _ screen: String) {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10),
                      "Keyboard must open in \(screen)")
        // Swipe in the editable content ABOVE the keyboard, not from the
        // system Home-indicator edge where iOS owns the gesture.
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.34))
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.12))
        lower.press(forDuration: 0.08, thenDragTo: upper)
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1),
                       "An upward swipe failed to hide the keyboard in \(screen)")
        XCTAssertFalse(app.buttons["keyboard.dismiss"].exists,
                       "No separate keyboard toolbar button in \(screen)")
    }

    func testUpwardSwipeDismissesNumericSecureMultilineAndDomainKeyboards() {
        let app = XCUIApplication()
        app.launchArguments += ["-setupGuideSeen.v1", "YES",
                                "-privacyDisclosureAccepted.v1", "YES",
                                "-appLanguage.v1", "ru"]
        app.launch()
        let profilesTab = app.tabBars.buttons["Профили"]
        XCTAssertTrue(profilesTab.waitForExistence(timeout: 20))
        profilesTab.tap()

        app.buttons["Добавить"].tap()
        let port = app.textFields["Порт"]
        XCTAssertTrue(port.waitForExistence(timeout: 12))
        port.tap()
        swipeUpToDismiss(app, "numeric proxy port")
        let password = app.secureTextFields["Пароль"]
        password.tap()
        swipeUpToDismiss(app, "proxy password")
        app.buttons["Отмена"].tap()

        app.buttons["profiles.import"].tap()
        let importedText = app.textViews.firstMatch
        XCTAssertTrue(importedText.waitForExistence(timeout: 12))
        importedText.tap()
        swipeUpToDismiss(app, "multiline proxy import")
        app.buttons["Закрыть"].tap()

        app.buttons["profiles.encryptedBackup"].tap()
        let backupPassword = app.secureTextFields["backup.export.password"]
        XCTAssertTrue(backupPassword.waitForExistence(timeout: 12))
        backupPassword.tap()
        swipeUpToDismiss(app, "encrypted backup")
        app.buttons["Закрыть"].tap()

        app.tabBars.buttons["Настройки"].tap()
        app.buttons["Исключения сайтов"].tap()
        let domain = app.textFields["Домен или IP"]
        XCTAssertTrue(domain.waitForExistence(timeout: 12))
        domain.tap()
        swipeUpToDismiss(app, "site exclusions")
    }
}
