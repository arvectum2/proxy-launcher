import XCTest

/// One narrow UI check for the new backup surface. It neither touches VPN
/// nor writes a file, and does not repeat the earlier proxy-import tests.
final class ProfileBackupUITests: XCTestCase {
    func testBackupControlsRequirePassphraseAndNeverAutoExport() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        let profiles = app.tabBars.buttons["Профили"]
        XCTAssertTrue(profiles.waitForExistence(timeout: 20))
        profiles.tap()
        let backup = app.buttons["profiles.encryptedBackup"]
        XCTAssertTrue(backup.waitForExistence(timeout: 10))
        backup.tap()
        XCTAssertTrue(app.staticTexts["Зашифрованная резервная копия"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Выбрать файл .aplbackup"].exists)
        let create = app.buttons["backup.export.create"]
        XCTAssertTrue(create.exists)
        XCTAssertFalse(create.isEnabled)
        XCTAssertTrue(app.secureTextFields["backup.export.password"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "Без пароля восстановить его невозможно"
        )).firstMatch.exists)
    }
}
