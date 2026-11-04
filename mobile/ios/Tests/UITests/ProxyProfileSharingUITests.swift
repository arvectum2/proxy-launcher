import XCTest

/// Sender-side proof uses ONLY the simulator-only .invalid profile fixture.
/// No real account, device Keychain, VPN connection or remote proxy is touched.
final class ProxyProfileSharingUITests: XCTestCase {
    func testSyntheticProfileShowsExplicitConsentThenScannableShareSheet() throws {
#if targetEnvironment(simulator)
        let app = XCUIApplication()
        app.launchArguments += [
            "-privacyDisclosureAccepted.v1", "YES",
            "-setupGuideSeen.v1", "YES",
            "-appLanguage.v1", "ru",
            "-aplBackupFilesQA"
        ]
        app.launch()
        let profiles = app.tabBars.buttons["Профили"]
        XCTAssertTrue(profiles.waitForExistence(timeout: 20))
        profiles.tap()
        let share = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "profiles.share.")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10), app.debugDescription)
        share.tap()
        let reveal = app.buttons["Показать QR-код"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "пароль")).firstMatch.exists)
        reveal.tap()
        let sender = app.buttons["profiles.share.sendQR"]
        XCTAssertTrue(sender.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.images["QR-код для импорта прокси"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "Делитесь только")).firstMatch.exists)
        // Do not transmit synthetic credentials or invoke any third-party
        // share extension during a routine UI test. The system Share button
        // is wired and accessible, and sender must be able to dismiss.
        app.buttons["Закрыть"].tap()
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "profiles.row.")).firstMatch.exists)
#else
        throw XCTSkip("QR sharing UI QA runs only on a disposable simulator")
#endif
    }
}
