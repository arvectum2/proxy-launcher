import XCTest

/// Safe QA of the same production Profiles UI in two long/RTL languages.
/// Uses a disposable .invalid fixture inserted only in Debug Simulator.
final class ProfileLibraryLocaleUITests: XCTestCase {
    func testGermanAndArabicLibraryControlsWithSyntheticFixture() {
        for language in ["de", "ar"] {
            let app = XCUIApplication()
            app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                    "-setupGuideSeen.v1", "YES",
                                    "-appLanguage.v1", language,
                                    "-aplBackupFilesQA"]
            app.launch()
            let tab = app.tabBars.buttons.element(boundBy: 1)
            XCTAssertTrue(tab.waitForExistence(timeout: 20), "Profiles tab \(language)")
            tab.tap()

            let search = app.textFields["profiles.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 12), "Search \(language)")
            let groupFilter = app.buttons["profiles.groupFilter"]
            XCTAssertTrue(groupFilter.exists, "Group filter \(language)")
            let rows = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@", "profiles.row."
            ))
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 12),
                          "Synthetic .invalid profile \(language)")
            XCTAssertGreaterThanOrEqual(rows.firstMatch.frame.height, 44)
            XCTAssertTrue(app.buttons["profiles.import"].exists)
            XCTAssertTrue(app.buttons["profiles.encryptedBackup"].exists)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "Localized profile library \(language) read-only"
            image.lifetime = .keepAlways
            add(image)
            app.terminate()
        }
    }
}
