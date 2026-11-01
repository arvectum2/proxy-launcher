import XCTest

/// Focused keyboard usability test: only disposable Simulator forms, no VPN,
/// stored proxy, password or user-device mutation.
final class KeyboardDismissUITests: XCTestCase {
    private func hideKeyboard(_ app: XCUIApplication, _ screen: String) {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10),
                      "Keyboard must open in \(screen)")
        let done = app.buttons["keyboard.dismiss"]
        XCTAssertTrue(done.waitForExistence(timeout: 10),
                      "Done toolbar must be visible in \(screen)")
        done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1),
                       "Keyboard remains open in \(screen)")
    }

    func testNumericTextEditorSecureAndDomainKeyboardsDismiss() {
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
        hideKeyboard(app, "numeric proxy port")
        let password = app.secureTextFields["Пароль"]
        password.tap()
        hideKeyboard(app, "proxy password")
        app.buttons["Отмена"].tap()

        app.buttons["profiles.import"].tap()
        let importedText = app.textViews.firstMatch
        XCTAssertTrue(importedText.waitForExistence(timeout: 12))
        importedText.tap()
        hideKeyboard(app, "multiline proxy import")
        app.buttons["Закрыть"].tap()

        app.buttons["profiles.encryptedBackup"].tap()
        let backupPassword = app.secureTextFields["backup.export.password"]
        XCTAssertTrue(backupPassword.waitForExistence(timeout: 12))
        backupPassword.tap()
        hideKeyboard(app, "encrypted backup")
        app.buttons["Закрыть"].tap()

        app.tabBars.buttons["Настройки"].tap()
        app.buttons["Исключения сайтов"].tap()
        let domain = app.textFields["Домен или IP"]
        XCTAssertTrue(domain.waitForExistence(timeout: 12))
        domain.tap()
        hideKeyboard(app, "site exclusions")
    }
}
