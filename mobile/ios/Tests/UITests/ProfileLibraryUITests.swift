import XCTest

/// One focused simulator journey: real production import -> library controls.
/// The reserved .invalid host avoids touching a real paid proxy.
final class ProfileLibraryUITests: XCTestCase {
    /// One explicit on-device share action, no real proxy or background upload.
    func testImportedSyntheticProxyShowsCredentialBearingQRWithoutStartingVPN() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Профили"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Профили"].tap()
        app.buttons["profiles.import"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let host = "share-" + UUID().uuidString.prefix(8).lowercased() + ".invalid"
        editor.tap()
        editor.typeText("socks5://testuser:qapass@" + host + ":47936")
        app.buttons["Проверить"].tap()
        XCTAssertTrue(app.staticTexts["Предпросмотр (1)"].waitForExistence(timeout: 10))
        app.swipeUp()
        let importButton = app.buttons["Импортировать профили"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10))
        importButton.tap()
        let search = app.textFields["profiles.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText(host)
        let share = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "profiles.share.")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10), app.debugDescription)
        share.tap()
        XCTAssertTrue(app.images["profiles.share.qrImage"].waitForExistence(timeout: 12),
                      app.debugDescription)
        XCTAssertTrue(app.buttons["profiles.share.systemSheet"].exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "может содержать логин и пароль")).firstMatch.exists)
        // The QR is shown only after a Share tap. Do not activate a tunnel
        // or transmit this intentionally synthetic credential anywhere.
        app.buttons["Закрыть"].tap()
    }

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
        let uniqueHost = "proxy-" + UUID().uuidString.prefix(8).lowercased() + ".invalid"
        editor.typeText(uniqueHost + ":47936")
        app.buttons["Проверить"].tap()
        XCTAssertTrue(app.staticTexts["Предпросмотр (1)"].waitForExistence(timeout: 10))
        app.swipeUp()
        let importProfiles = app.buttons["Импортировать профили"]
        XCTAssertTrue(importProfiles.waitForExistence(timeout: 10))
        importProfiles.tap()

        let search = app.textFields["profiles.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText(uniqueHost)
        let favorite = app.buttons["В избранное"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        favorite.tap()
        XCTAssertTrue(app.buttons["Убрать из избранного"].firstMatch.exists)

        // Assign a group using the same menu used by bulk actions.
        let group = app.buttons["Группа профиля"].firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 10))
        group.tap()
        app.buttons["Рабочие"].tap()
        XCTAssertTrue(app.staticTexts["Рабочие"].waitForExistence(timeout: 10))

        // Filtering must never expose a hidden profile to bulk deletion.
        let groupFilter = app.buttons["profiles.groupFilter"]
        XCTAssertTrue(groupFilter.exists)
        groupFilter.tap()
        app.buttons["Избранные"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profiles.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 1, "Only the uniquely imported synthetic profile is visible")

        app.buttons["profiles.bulk.toggle"].tap()
        rows.firstMatch.tap()
        let bulkDelete = app.buttons["profiles.bulk.delete"]
        if !bulkDelete.isHittable { app.swipeUp() }
        XCTAssertTrue(bulkDelete.waitForExistence(timeout: 10))
        XCTAssertTrue(bulkDelete.isEnabled)
        let snapshot = XCTAttachment(screenshot: app.screenshot())
        snapshot.name = "Profile library filtered bulk actions (synthetic .invalid)"
        snapshot.lifetime = .keepAlways
        add(snapshot)
        bulkDelete.tap()
        let confirmDeletion = app.buttons["Удалить безвозвратно"]
        XCTAssertTrue(confirmDeletion.waitForExistence(timeout: 10))
        confirmDeletion.tap()
        XCTAssertTrue(app.staticTexts["Нет профилей по выбранному фильтру"].waitForExistence(timeout: 10) ||
                      !rows.firstMatch.exists)
    }
}
