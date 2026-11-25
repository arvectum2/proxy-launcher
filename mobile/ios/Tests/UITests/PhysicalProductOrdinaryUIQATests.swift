import XCTest
#if APL_RUN_EXPLICIT_PRODUCT_UI_QA && !targetEnvironment(simulator)
@MainActor final class PhysicalProductOrdinaryUIQATests:XCTestCase {
    // Test only the actual visible ordinary controls. No direct VPN start API.
    private func reveal(_ element:XCUIElement,app:XCUIApplication,up:Bool=true)throws {
        for _ in 0..<8 {
            if element.exists && element.isHittable{return}
            if up {app.swipeUp()}else{app.swipeDown()}
        }
        guard element.exists && element.isHittable else{
            XCTFail("Required synthetic UI control not visible: "+element.identifier)
            throw NSError(domain:"APLProductUIQA",code:1)
        }
    }
    func testSyntheticImportSelectionHomeConnectDisconnect()throws {
        continueAfterFailure=false
        let app=XCUIApplication(bundleIdentifier:"ru.arvectum.proxylauncher.ios")
        app.launchArguments=["--apl-authorized-product-ui-qa","-appLanguage.v1","en"]
        app.launch()
        defer {
            // Do not automatically re-connect or touch other apps' VPNs.
            let stop=app.buttons["Disconnect"]
            if stop.exists && stop.isHittable {stop.tap()}
            let clean=app.buttons["QA Cleanup"]
            if clean.exists && clean.isHittable && clean.isEnabled {clean.tap()}
        }
        let review=app.buttons["Continue to review"]
        XCTAssertTrue(review.waitForExistence(timeout:15))
        try reveal(review,app:app);review.tap()
        let save=app.buttons["Save reviewed profiles"]
        XCTAssertTrue(save.waitForExistence(timeout:10))
        try reveal(save,app:app);save.tap()
        let actions=app.buttons["Profile actions"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout:10))
        try reveal(actions,app:app,up:false);actions.tap()
        let select=app.buttons["Select"]
        XCTAssertTrue(select.waitForExistence(timeout:5));select.tap()
        let confirm=app.buttons["Confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout:8));try reveal(confirm,app:app);confirm.tap()
        let close=app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout:5));close.tap()
        XCTAssertTrue(close.waitForExistence(timeout:5));close.tap()
        XCTAssertTrue(app.staticTexts["Peer ready — tap Home Connect"].waitForExistence(timeout:35))
        let connect=app.buttons["Connect"]
        XCTAssertTrue(connect.waitForExistence(timeout:5));XCTAssertTrue(connect.isEnabled)
        XCTAssertTrue(app.buttons["Proxy: vlessReality"].exists || app.staticTexts["vlessReality"].exists)
        connect.tap()
        let stop=app.buttons["Disconnect"]
        XCTAssertTrue(stop.waitForExistence(timeout:12))
        XCTAssertTrue(app.staticTexts["Receipt PASS — tap Home Disconnect"].waitForExistence(timeout:8))
        stop.tap()
        XCTAssertTrue(app.staticTexts["Home disconnect confirmed — QA Cleanup"].waitForExistence(timeout:10))
        XCTAssertTrue(connect.waitForExistence(timeout:5))
        let clean=app.buttons["QA Cleanup"];XCTAssertTrue(clean.isEnabled);clean.tap()
        XCTAssertTrue(app.staticTexts["UI QA cleaned"].waitForExistence(timeout:12))
    }
}
#endif
