import XCTest
#if APL_NATIVE_PROFILE_REVIEW && APL_RUN_EXPLICIT_NATIVE_FILES_QA && targetEnvironment(simulator)
/// Run only on an explicitly provisioned disposable simulator.
final class NativeFilesReviewUITests:XCTestCase {
    private let files=XCUIApplication(bundleIdentifier:"com.apple.DocumentsApp")
    private func reveal(_ element:XCUIElement,in app:XCUIApplication,top:Bool=false,file:StaticString=#filePath,line:UInt=#line)throws {
        for _ in 0..<7 {if element.exists && element.isHittable{return};if top{app.swipeDown()}else{app.swipeUp()}}
        XCTFail("Element unavailable: \(element.identifier)",file:file,line:line);throw NSError(domain:"NativeFilesQA",code:1)
    }
    private func screenshot(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    private func item(_ name:String,in app:XCUIApplication)->XCUIElement? {
        for target in [app] + (files.state == .runningForeground ? [files] : []) {
            for type:XCUIElement.ElementType in [.cell,.button,.staticText,.other] {
                let q=target.descendants(matching:type).matching(NSPredicate(format:"label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@ OR identifier == %@",name,name+",",name+".",name)).firstMatch
                if q.exists && q.isHittable{return q}
            }
        }
        return nil
    }
    private func tap(_ name:String,in app:XCUIApplication)throws {
        if let q=item(name,in:app){q.tap();return}
        screenshot("Missing-"+name);XCTFail("System control not accessible: \(name)");throw NSError(domain:"NativeFilesQA",code:2)
    }
    func testFilesImportAndEncryptedRoundtrip()throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments += ["-privacyDisclosureAccepted.v1","YES","-setupGuideSeen.v1","YES","-appLanguage.v1","en"];app.launch()
        let tab=app.tabBars.buttons["Profiles"];XCTAssertTrue(tab.waitForExistence(timeout:20));tab.tap()
        let entry=app.buttons["profiles.nativeReviewQA"];XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
        let count=app.staticTexts["nativeQA.count"]
        func counts(_ n:Int)throws{try reveal(count,in:app,top:true);XCTAssertEqual(count.label,"Temporary profiles: \(n)")}
        try counts(0);let choose=app.buttons["nativeQA.autoFiles"];try reveal(choose,in:app);choose.tap();Thread.sleep(forTimeInterval:2);screenshot("Import-open")
        if item("APL-QA-WG",in:app)==nil {
            if let browse=item("Browse",in:app){browse.tap();Thread.sleep(forTimeInterval:1)}
            if item("On My iPhone",in:app) != nil{try tap("On My iPhone",in:app);Thread.sleep(forTimeInterval:1)}
            if let folder=item("Arvectum Proxy Launcher",in:app),!folder.label.contains("Actions Menu"){folder.tap();Thread.sleep(forTimeInterval:1)}
            else if item("On My iPhone",in:app) != nil {
                // Verified location screen with one synthetic APL folder (attachment Import-folder).
                app.coordinate(withNormalizedOffset:CGVector(dx:0.18,dy:0.29)).tap();Thread.sleep(forTimeInterval:1)
            }
        }
        screenshot("Import-folder")
        if item("APL-QA-WG",in:app)==nil || item("APL-QA-AWG",in:app)==nil {
            // Never guess document locations; attach actual system hierarchy for diagnosis.
            let a=XCTAttachment(string:app.debugDescription);a.name="Files-hierarchy";a.lifetime = .keepAlways;add(a)
            XCTFail("Synthetic document controls unavailable in Files hierarchy");return
        }
        try tap("APL-QA-WG",in:app);try tap("APL-QA-AWG",in:app);try tap("Open",in:app)
        try reveal(app.staticTexts["WireGuard: 1"],in:app);try reveal(app.staticTexts["AmneziaWG 1: 1"],in:app);try counts(0)
        let confirm=app.buttons["nativeQA.confirmImport"];try reveal(confirm,in:app);confirm.tap();try counts(2)
        let prepare=app.buttons["nativeQA.prepareExport"];try reveal(prepare,in:app);prepare.tap()
        let pass="Synthetic-QA-Backup-2026",p=app.secureTextFields["nativeQA.exportPassword"],repeatField=app.secureTextFields["nativeQA.repeatPassword"]
        try reveal(p,in:app);p.tap();p.typeText(pass);try reveal(repeatField,in:app);repeatField.tap();repeatField.typeText(pass)
        let encrypt=app.buttons["nativeQA.encrypt"];try reveal(encrypt,in:app);XCTAssertTrue(encrypt.isEnabled);encrypt.tap();Thread.sleep(forTimeInterval:2);screenshot("Export-open");try tap("Save",in:app)
        try reveal(app.staticTexts["nativeQA.exportSaved"],in:app);app.buttons["Close"].tap();try reveal(entry,in:app,top:true);entry.tap();try counts(0)
        let backup=app.buttons["nativeQA.chooseBackup"];try reveal(backup,in:app);backup.tap();Thread.sleep(forTimeInterval:2);screenshot("Restore-open")
        guard let doc=([app] + (files.state == .runningForeground ? [files] : [])).compactMap({target -> XCUIElement? in let q=target.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH %@","APL-Native-QA-Encrypted-")).firstMatch;return q.exists && q.isHittable ? q:nil}).first else {XCTFail("Saved encrypted document not accessible");return};doc.tap()
        let restore=app.secureTextFields["nativeQA.restorePassword"];try reveal(restore,in:app);restore.tap();restore.typeText(pass);let review=app.buttons["nativeQA.reviewBackup"];try reveal(review,in:app);review.tap()
        try reveal(app.staticTexts["WireGuard: 1"],in:app);try reveal(app.staticTexts["AmneziaWG 1: 1"],in:app);try counts(0);try reveal(confirm,in:app);confirm.tap();try counts(2)
        XCUIDevice.shared.press(.home);app.activate();try counts(0)
    }
}
#endif
