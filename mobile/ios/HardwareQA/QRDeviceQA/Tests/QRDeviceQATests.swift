import XCTest

/// Physical iPhone only; the QA target never installs the production bundle.
final class QRDeviceQATests: XCTestCase {
    func testQRCodecAndSenderConsent() {
        let app = XCUIApplication()
        app.launch()
        let button = app.buttons["qa.run-selftest"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Только синтетический прокси .invalid"].exists)
        button.tap()
        XCTAssertTrue(app.staticTexts[
            "PASS: QR pixels decoded and profile matched on hardware"
        ].waitForExistence(timeout: 15), app.debugDescription)

        app.buttons["qa.open-share"].tap()
        let confirm = app.buttons["Подтверждаю показ"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["profiles.share.sendQR"].exists)
        confirm.tap()
        XCTAssertTrue(app.buttons["profiles.share.sendQR"]
            .waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.images["QR-код для импорта прокси"].exists)
        app.buttons["Закрыть"].tap()
        XCTAssertTrue(button.waitForExistence(timeout: 10))
    }
}
