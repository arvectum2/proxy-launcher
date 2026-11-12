import XCTest

/// Device-only release acceptance. Never imports, edits, deletes, connects or
/// switches VPN. Existing user profile names and credentials are not logged.
final class PhysicalUpgradeReadOnlyUITests: XCTestCase {
    func testExistingThreeProfilesAreVisibleAfterInPlaceUpgrade() throws {
        // This assertions depends on the owner's preexisting three profiles.
        // Never run it on fresh CI/simulator installs with empty user data.
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone-only migration acceptance")
        #endif

        let app = XCUIApplication()
        // Do not supply launch arguments: testing must use real persisted
        // App Group and Keychain state, not launch-argument QA fixtures.
        app.launch()
        let profilesTab = app.tabBars.buttons["Профили"]
        XCTAssertTrue(profilesTab.waitForExistence(timeout: 25),
                      "Expected the existing Russian user session")
        profilesTab.tap()

        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "profiles.row.")
        )
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(rows.count, 3,
                       "Expected all 3 previously saved profiles, no imports or deletes")

        // Ensure the library can navigate back without activating the VPN.
        let settingsTab = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settingsTab.exists)
        settingsTab.tap()
        XCTAssertTrue(app.staticTexts["0.3.0"].waitForExistence(timeout: 10),
                      "The installed binary must show iOS 0.3.0")
    }
}
