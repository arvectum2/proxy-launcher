import XCTest

final class SmartExclusionsUITests: XCTestCase {
    func testAddDeleteAndCancelWithoutSaving() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let exclusions = app.buttons["Исключения сайтов"]
        XCTAssertTrue(exclusions.waitForExistence(timeout: 10))
        exclusions.tap()
        let field = app.textFields["example.com"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("example.com")
        app.buttons["Добавить"].tap()
        XCTAssertTrue(app.staticTexts["example.com"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Найти связанные домены для example.com"].exists)
        app.buttons["Удалить исключение example.com"].tap()
        XCTAssertFalse(app.staticTexts["example.com"].exists)
        app.buttons["Отмена"].tap()
        XCTAssertTrue(exclusions.waitForExistence(timeout: 5))
    }

    func testUndoRestoresDeletedEntryBeforeSave() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        app.tabBars.buttons["Настройки"].tap()
        app.buttons["Исключения сайтов"].tap()
        let field = app.textFields["example.com"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("example.com")
        app.buttons["Добавить"].tap()
        XCTAssertTrue(app.buttons["Удалить исключение example.com"].exists)
        app.buttons["Удалить исключение example.com"].tap()
        XCTAssertFalse(app.buttons["Удалить исключение example.com"].exists)
        let undo = app.buttons["Отменить последнее изменение"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(app.buttons["Удалить исключение example.com"].waitForExistence(timeout: 5))
        app.buttons["Отмена"].tap()
    }

    func testWebKitScanReturnsResultForExampleCom() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        app.buttons["Исключения сайтов"].tap()
        let field = app.textFields["example.com"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("example.com")
        app.buttons["Найти связанные домены"].tap()
        XCTAssertTrue(app.staticTexts["Анализ ресурсов сайта"].waitForExistence(timeout: 5))
        let empty = app.staticTexts["Новых связанных доменов не обнаружено"]
        XCTAssertTrue(empty.waitForExistence(timeout: 23), "Expected only the original host for example.com; labels: \(app.staticTexts.allElementsBoundByIndex.map { $0.label })")
    }

    func testCancelWebKitScanAllowsRestart() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        app.buttons["Исключения сайтов"].tap()
        let field = app.textFields["example.com"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("example.com")
        app.buttons["Найти связанные домены"].tap()
        let cancel = app.buttons["Отменить анализ"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertFalse(app.staticTexts["Анализ ресурсов сайта"].exists)
        XCTAssertTrue(app.buttons["Найти связанные домены"].isEnabled)
        app.buttons["Найти связанные домены"].tap()
        XCTAssertTrue(app.staticTexts["Новых связанных доменов не обнаружено"].waitForExistence(timeout: 23))
    }

    func testExclusionsScreenAndValidation() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let exclusions = app.buttons["Исключения сайтов"]
        XCTAssertTrue(exclusions.waitForExistence(timeout: 10))
        exclusions.tap()
        XCTAssertTrue(app.navigationBars["Исключения сайтов"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Найти связанные домены"].exists)
        XCTAssertFalse(app.buttons["Найти связанные домены"].isEnabled)
        let field = app.textFields["example.com"]
        XCTAssertTrue(field.exists)
        field.tap()
        field.typeText("127.0.0.1")
        app.buttons["Найти связанные домены"].tap()
        XCTAssertTrue(app.staticTexts["Для поиска зависимостей укажите корректный домен сайта, а не IP-адрес"].waitForExistence(timeout: 5))
    }
}


final class ProxyImportUITests: XCTestCase {
    func testImportPreviewForValidLink() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        let profiles = app.tabBars.buttons["Профили"]
        XCTAssertTrue(profiles.waitForExistence(timeout: 20))
        profiles.tap()
        let importButton = app.buttons["Импортировать прокси"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10))
        importButton.tap()
        XCTAssertTrue(app.navigationBars["Импорт прокси"].waitForExistence(timeout: 10))
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.exists)
        editor.tap()
        editor.typeText("http://proxy.example:8080")
        app.buttons["Проверить"].tap()
        XCTAssertTrue(app.staticTexts["Предпросмотр (1)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Импортировать профили"].exists)
    }
}

extension ProxyImportUITests {
    private func allowCameraPermissionIfPrompted() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(identifier: "kTCCServiceCamera-allow-button").firstMatch
        if allow.waitForExistence(timeout: 2) { allow.tap() }
    }

    func testQRScannerOpensAndCanBeClosed() {
        let app = XCUIApplication()
        allowCameraPermissionIfPrompted()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        allowCameraPermissionIfPrompted()
        let profiles = app.tabBars.buttons["Профили"]
        XCTAssertTrue(profiles.waitForExistence(timeout: 20))
        profiles.tap()
        let importButton = app.buttons["Импортировать прокси"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10))
        importButton.tap()
        let scanButton = app.buttons["Сканировать QR-код"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 10))
        scanButton.tap()
        allowCameraPermissionIfPrompted()
#if targetEnvironment(simulator)
        // iOS Simulator has no real camera input; the production scanner must
        // fail gracefully with an explanation, not pretend to scan a code.
        XCTAssertTrue(app.staticTexts["Камера недоступна"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Импорт прокси"].waitForExistence(timeout: 8))
#else
        XCTAssertTrue(app.navigationBars["Сканирование QR"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Камера готова — наведите на QR-код"].waitForExistence(timeout: 20))
        app.buttons["Отмена"].tap()
        XCTAssertTrue(app.navigationBars["Импорт прокси"].waitForExistence(timeout: 8))
#endif
    }

    func testEditingLinkInvalidatesPreview() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        let profiles = app.tabBars.buttons["Профили"]
        XCTAssertTrue(profiles.waitForExistence(timeout: 20))
        profiles.tap()
        app.buttons["Импортировать прокси"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("http://proxy.example:8080")
        app.buttons["Проверить"].tap()
        XCTAssertTrue(app.staticTexts["Предпросмотр (1)"].waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("broken")
        XCTAssertFalse(app.staticTexts["Предпросмотр (1)"].exists)
        XCTAssertFalse(app.buttons["Импортировать профили"].exists)
    }
}

final class SmartExclusionsLocaleUITests: XCTestCase {
    private func assertLocalizedSmartExclusions(language: String, settings: String,
                                                exclusions: String, scan: String) {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES",
                                "-appLanguage.v1", language]
        app.launch()
        let tab = app.tabBars.buttons[settings]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Settings tab absent for \(language)")
        tab.tap()
        let section = app.buttons[exclusions]
        XCTAssertTrue(section.waitForExistence(timeout: 10), "Exclusions item absent for \(language)")
        section.tap()
        XCTAssertTrue(app.buttons[scan].waitForExistence(timeout: 10),
                      "Localized Smart Exclusions CTA absent for \(language)")
        XCTAssertTrue(app.textFields["example.com"].exists)
    }

    func testEnglishSmartExclusionsScreenUsesEnglishLabels() {
        assertLocalizedSmartExclusions(language: "en", settings: "Settings",
                                       exclusions: "Website exclusions", scan: "Find related domains")
    }

    func testHebrewSmartExclusionsScreenUsesRTLLanguageLabels() {
        assertLocalizedSmartExclusions(language: "he", settings: "הגדרות",
                                       exclusions: "חריגים לאתרים", scan: "חיפוש דומיינים קשורים")
    }
}

final class QuickActionsUITests: XCTestCase {
    func testEnglishQuickActionsHelp() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "en"]
        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let quick = app.buttons["settings.quickActions"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        quick.tap()
        XCTAssertTrue(app.navigationBars["VPN quick actions"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Connect APL"].exists)
        XCTAssertTrue(app.staticTexts["Disconnect APL"].exists)
        XCTAssertTrue(app.staticTexts["Toggle APL"].exists)
        XCTAssertTrue(app.links["quickActions.openShortcuts"].exists)
    }
}
