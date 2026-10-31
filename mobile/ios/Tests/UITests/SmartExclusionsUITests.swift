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
        let empty = app.staticTexts["Связанные домены не обнаружены"]
        XCTAssertTrue(empty.waitForExistence(timeout: 23), "Expected only the original host for example.com; labels: \(app.staticTexts.allElementsBoundByIndex.map { $0.label })")
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
