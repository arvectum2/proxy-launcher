import XCTest

/// One focused simulator journey: real production import -> library controls.
/// The reserved .invalid host avoids touching a real paid proxy.
final class ProfileLibraryUITests: XCTestCase {
    func testImportedProxyCanBeFoundFavoritedAndRemovedWithoutStartingVPN() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        let profiles = app.tabBars.buttons["Профили"]
        XCTAssertTrue(profiles.waitForExistence(timeout: 20))
        profiles.tap()
        let importer = app.buttons["profiles.import"]
        XCTAssertTrue(importer.waitForExistence(timeout: 10))
        importer.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("proxy-020-qa.invalid:47936")
        app.buttons["Проверить"].tap()
        XCTAssertTrue(app.staticTexts["Предпросмотр (1)"].waitForExistence(timeout: 10))
        app.swipeUp()
        let importProfiles = app.buttons["Импортировать профили"]
        XCTAssertTrue(importProfiles.waitForExistence(timeout: 10))
        importProfiles.tap()

        let search = app.textFields["profiles.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("proxy-020-qa.invalid")
        let favorite = app.buttons["В избранное"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        favorite.tap()
        XCTAssertTrue(app.buttons["Убрать из избранного"].firstMatch.exists)

        app.buttons["Выбрать"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profiles.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        rows.firstMatch.tap()
        let bulkDelete = app.buttons["Удалить выбранные (1)"]
        XCTAssertTrue(bulkDelete.waitForExistence(timeout: 10))
        bulkDelete.tap()
        let confirmDeletion = app.buttons["Удалить безвозвратно"]
        XCTAssertTrue(confirmDeletion.waitForExistence(timeout: 10))
        confirmDeletion.tap()
        XCTAssertTrue(app.staticTexts["Нет профилей по выбранному фильтру"].waitForExistence(timeout: 10) ||
                      !rows.firstMatch.exists)
    }
}
