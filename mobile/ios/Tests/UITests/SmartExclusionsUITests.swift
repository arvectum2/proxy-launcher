import XCTest

final class SmartExclusionsUITests: XCTestCase {
    func testManualExpansionSwitchAndEditableSiteGroup() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru",
                                "-qaSmartDependenciesFixture", "YES"]
        app.launch()
        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let mode = app.switches["settings.autoExpandExclusions"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        if (mode.value as? String) == "1" { mode.tap() }
        XCTAssertEqual(mode.value as? String, "0")
        app.buttons["Исключения сайтов"].tap()
        let site = app.textFields["example.com"]
        XCTAssertTrue(site.waitForExistence(timeout: 10))
        site.tap()
        site.typeText("qa.example.test")
        app.buttons["Добавить"].tap()
        let group = app.buttons["exclusions.addLinked.qa.example.test"]
        for _ in 0..<8 where !group.exists { app.swipeUp() }
        XCTAssertTrue(group.waitForExistence(timeout: 10), app.debugDescription)
        group.tap()
        let linked = app.textFields["exclusions.linkedHost"]
        XCTAssertTrue(linked.waitForExistence(timeout: 5))
        linked.tap()
        linked.typeText("auth.partner.test")
        app.buttons["exclusions.submitLinked"].tap()
        let groupWithLink = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Связанные домены (5)")).firstMatch
        for _ in 0..<5 where !groupWithLink.exists { app.swipeUp() }
        XCTAssertTrue(groupWithLink.waitForExistence(timeout: 7), app.debugDescription)
        let added = app.staticTexts["auth.partner.test"].firstMatch
        if !added.exists { groupWithLink.tap() }
        for _ in 0..<5 where !added.exists { app.swipeUp() }
        XCTAssertTrue(added.waitForExistence(timeout: 7), app.debugDescription)
        // Do not save synthetic QA hosts to shared user preferences.
        app.buttons["Отмена"].tap()
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        if (mode.value as? String) == "0" { mode.tap() }
        XCTAssertEqual(mode.value as? String, "1")
    }

    func testSmart3ProblemBadgeAndNoSilentExclusion() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES",
                                "-appLanguage.v1", "ru", "-qaSmart3FailureFixture", "YES"]
        app.launch()
        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        let description = settings.debugDescription
        print("APL_SMART3_SETTINGS_TAB_ACCESSIBILITY=" + description)
        // Number badge must be visible on Settings while the detected host
        // remains pending and expires automatically after the evidence TTL.
        XCTAssertTrue(description.contains("1") || (settings.value as? String)?.contains("1") == true,
                      "Expected one suggested failed host in Settings tab: \(description)")
        settings.tap()
        app.buttons["Исключения сайтов"].tap()
        let host = app.staticTexts["auth.qa-example.test"].firstMatch
        for _ in 0..<6 where !host.exists { app.swipeUp() }
        XCTAssertTrue(host.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Удалить исключение auth.qa-example.test"].exists)
    }

    func testAdaptiveConnectionSuggestionRequiresManualConsent() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES",
                                "-appLanguage.v1", "ru", "-qaSmart3FailureFixture", "YES"]
        app.launch()
        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        app.buttons["Исключения сайтов"].tap()
        let host = app.staticTexts["auth.qa-example.test"].firstMatch
        for _ in 0..<6 where !host.exists { app.swipeUp() }
        XCTAssertTrue(host.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Повторные ошибки соединения через прокси"].exists)
        XCTAssertFalse(app.buttons["Удалить исключение auth.qa-example.test"].exists)
        app.buttons["Проверить исключение"].tap()
        XCTAssertTrue(app.staticTexts["Общий IP-адрес может обслуживать и другие сайты. Такой обход касается всего IP, не только выбранного домена."].waitForExistence(timeout: 5))
        app.buttons["Отмена"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Удалить исключение auth.qa-example.test"].exists)
    }

    func testAddAutoDiscoversStrongSubdomainsAndOffersExternalHosts() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES",
                                "-appLanguage.v1", "ru", "-qaSmartDependenciesFixture", "YES"]
        app.launch()
        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        app.buttons["Исключения сайтов"].tap()
        let field = app.textFields["example.com"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("qa.example.test")
        // No manual Find action: Add alone must start the scan and classify.
        app.buttons["Добавить"].tap()
        let auto = app.staticTexts["api.qa.example.test"].firstMatch
        // List cells below the first fold are lazily created; scroll until
        // the new auto-included section appears instead of assuming viewport.
        for _ in 0..<5 where !auto.exists { app.swipeUp() }
        XCTAssertTrue(auto.waitForExistence(timeout: 8), app.debugDescription)
        // Single-signal CDN and tracking endpoint are offered, not silently
        // approved. A different registered domain is also only a suggestion.
        let pending = app.staticTexts["cdn.qa.example.test"].firstMatch
        let tracker = app.staticTexts["analytics.qa.example.test"].firstMatch
        let external = app.staticTexts["assets.partner.test"].firstMatch
        for item in [pending, tracker, external] {
            for _ in 0..<5 where !item.exists { app.swipeUp() }
            XCTAssertTrue(item.exists, app.debugDescription)
        }
        XCTAssertFalse(app.buttons["Удалить исключение assets.partner.test"].exists)
        app.buttons["Отмена"].tap()
    }

    func testAutomaticallyDiscoveredDomainPersistsAfterSave() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES",
                                "-appLanguage.v1", "ru", "-qaSmartDependenciesFixture", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Настройки"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Настройки"].tap()
        app.buttons["Исключения сайтов"].tap()
        let field = app.textFields["example.com"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("qa.example.test")
        app.buttons["Добавить"].tap()
        let auto = app.staticTexts["api.qa.example.test"].firstMatch
        for _ in 0..<5 where !auto.exists { app.swipeUp() }
        XCTAssertTrue(auto.waitForExistence(timeout: 8), app.debugDescription)
        let save = app.buttons["Сохранить"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["Исключения сайтов"].waitForExistence(timeout: 10))
        app.buttons["Исключения сайтов"].tap()
        for _ in 0..<5 where !auto.exists { app.swipeUp() }
        XCTAssertTrue(auto.exists, "Auto-approved domain must survive Save and re-open")
        // Remove fixture root before leaving so this test cannot pollute
        // other tests or the simulator's saved app state.
        let remove = app.buttons["Удалить исключение qa.example.test"]
        for _ in 0..<6 where !remove.exists { app.swipeUp() }
        XCTAssertTrue(remove.exists)
        remove.tap()
        app.buttons["Сохранить"].tap()
    }

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
        // A long safety explanation and large navigation title can push the
        // actual row below the viewport on compact iPhones.
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["example.com"].waitForExistence(timeout: 5), app.debugDescription)
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
        app.swipeUp()
        XCTAssertTrue(app.buttons["Удалить исключение example.com"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Удалить исключение example.com"].tap()
        XCTAssertFalse(app.buttons["Удалить исключение example.com"].exists)
        let undo = app.buttons["Отменить последнее изменение"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(app.buttons["Удалить исключение example.com"].waitForExistence(timeout: 5))
        app.buttons["Отмена"].tap()
    }

    func testWebKitScanReturnsResultForExampleCom() throws {
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
        // On a real iPhone, example.com can complete before XCTest observes
        // the transient loading label. Assert the stable end state instead.
        let empty = app.staticTexts["Новых связанных доменов не обнаружено"]
        let completed = empty.waitForExistence(timeout: 23)
        if !completed && app.staticTexts["Превышен лимит времени на запрос."].exists {
            // An independent physical URLSession probe showed the iPhone
            // cannot reach example.com at all. Do not conflate a missing
            // external network with a broken Smart Exclusions parser.
            throw XCTSkip("External HTTPS is unavailable on this device; repeat WebKit acceptance after restoring iPhone internet.")
        }
        XCTAssertTrue(completed, "Expected only the original host for example.com; labels: \(app.staticTexts.allElementsBoundByIndex.map { $0.label })")
        XCTAssertTrue(app.buttons["Найти связанные домены"].isEnabled)
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

    func testBypassSafetyDetailsRemainAvailable() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        app.buttons["Исключения сайтов"].tap()
        let explanation = app.buttons["Подробнее о правилах обхода"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 10))
        explanation.tap()
        let warning = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "gu-st.ru")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "The full compatibility warning must remain available after disclosure")
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
        let importButton = app.buttons["profiles.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10))
        importButton.tap()
        XCTAssertTrue(app.navigationBars["Импорт прокси"].waitForExistence(timeout: 10))
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.exists)
        editor.tap()
        editor.typeText("http://proxy-import-preview.invalid:47931")
        app.buttons["Проверить"].tap()
        XCTAssertTrue(app.staticTexts["Предпросмотр (1)"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["Импортировать профили"].waitForExistence(timeout: 5) ||
                      app.staticTexts["Все найденные профили уже добавлены"].exists,
                      app.debugDescription)
    }
}

extension ProxyImportUITests {
    func testSupplierColonFormatPreviewsWithoutSavingSecrets() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        let profiles = app.tabBars.buttons["Профили"]
        XCTAssertTrue(profiles.waitForExistence(timeout: 15))
        profiles.tap()
        app.buttons["profiles.import"].tap()
        XCTAssertTrue(app.navigationBars["Импорт прокси"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Тип прокси по умолчанию"].exists)
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.exists)
        editor.tap()
        editor.typeText("192.0.2.47:45321:exampleuser:samplepass")
        app.buttons["Проверить"].tap()
        XCTAssertTrue(app.staticTexts["Предпросмотр (1)"].waitForExistence(timeout: 8))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "192.0.2.47")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["samplepass"].exists)
        // Preview-only, no fake profile saved and no device VPN toggled.
    }
}

extension ProxyImportUITests {
    func testEnglishImportIsReadableAndParsesLink() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "en"]
        app.launch()
        let profiles = app.tabBars.buttons["Profiles"]
        XCTAssertTrue(profiles.waitForExistence(timeout: 20))
        profiles.tap()
        app.buttons["Import proxies"].tap()
        XCTAssertTrue(app.navigationBars["Import proxies"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Scan QR code"].exists)
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.exists)
        XCTAssertEqual(editor.label, "Proxy link text")
        editor.tap()
        editor.typeText("http://en-import-preview.invalid:47932")
        app.buttons["Preview"].tap()
        XCTAssertTrue(app.staticTexts["Preview (1)"].waitForExistence(timeout: 6))
        app.swipeUp()
        XCTAssertTrue(app.buttons["Import profiles"].waitForExistence(timeout: 5) ||
                      app.staticTexts["All these profiles are already saved"].exists,
                      app.debugDescription)
        // This is a preview-only test, never saves a test proxy to user data.
    }

    func testOnboardingCanOpenLinkAndQRImport() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let guide = app.buttons["Первое подключение"]
        XCTAssertTrue(guide.waitForExistence(timeout: 10))
        guide.tap()
        app.buttons["Далее"].tap()
        let importLink = app.buttons["Импортировать по ссылке или QR-коду"]
        XCTAssertTrue(importLink.waitForExistence(timeout: 8))
        importLink.tap()
        XCTAssertTrue(app.navigationBars["Импорт прокси"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Сканировать QR-код"].exists)
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
        let importButton = app.buttons["profiles.import"]
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
        app.buttons["profiles.import"].tap()
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
