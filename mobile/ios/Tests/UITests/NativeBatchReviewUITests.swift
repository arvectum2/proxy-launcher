import XCTest
#if APL_NATIVE_PROFILE_REVIEW && targetEnvironment(simulator)
import CryptoKit

/// Disposable simulator only. No clipboard, Keychain or VPN operations.
final class NativeBatchReviewUITests:XCTestCase {
    func testAutomaticTextPreviewSelectionRemovalAndDismissal()throws {
        let app=XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1","YES","-setupGuideSeen.v1","YES","-appLanguage.v1","en"]
        app.launch()
        let tab=app.tabBars.buttons["Profiles"]
        XCTAssertTrue(tab.waitForExistence(timeout:20));tab.tap()
        let entry=app.buttons["profiles.nativeReviewQA"]
        XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
        func reveal(_ element:XCUIElement,top:Bool=false,file:StaticString=#filePath,line:UInt=#line) {
            for _ in 0..<7 {
                if element.exists && element.isHittable {return}
                if top {app.swipeDown()}else{app.swipeUp()}
            }
            XCTAssertTrue(element.exists && element.isHittable,"Element unavailable",file:file,line:line)
        }
        let count=app.staticTexts["nativeQA.count"]
        func assertCount(_ n:Int){reveal(count,top:true);XCTAssertEqual(count.label,"Temporary profiles: \(n)")}
        XCTAssertTrue(count.waitForExistence(timeout:10));assertCount(0)
        let key=Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        let source=(0..<2).map{_ in "vless://\(UUID().uuidString.lowercased())@192.0.2.43:443?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk=\(key)&sid=abcd"}.joined(separator:"\n")
        let field=app.textViews["nativeQA.pastedText"];XCTAssertTrue(field.exists);field.tap();field.typeText(source)
        let preview=app.buttons["nativeQA.previewText"];XCTAssertTrue(preview.isEnabled);preview.tap()
        reveal(app.staticTexts["VLESS Reality: 2"]);assertCount(0)
        let confirm=app.buttons["nativeQA.confirmImport"];reveal(confirm);confirm.tap();assertCount(2)
        let select=app.buttons["nativeQA.select.1"];reveal(select);select.tap();XCTAssertTrue(app.staticTexts["Selected for review"].exists)
        let remove=app.buttons["nativeQA.remove.1"];reveal(remove);remove.tap();assertCount(2)
        let confirmRemoval=app.buttons["nativeQA.confirmRemoval"];reveal(confirmRemoval);confirmRemoval.tap();assertCount(1)
        app.buttons["Close"].tap();reveal(entry,top:true);entry.tap();assertCount(0)
    }
}
#endif
