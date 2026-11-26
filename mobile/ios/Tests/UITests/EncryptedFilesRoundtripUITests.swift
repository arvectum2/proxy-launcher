import XCTest

/// Only runs on the dedicated QA simulator. Explicit debug-only app arg
/// creates a synthetic .invalid proxy and Keychain entry, never a real device.
/// Unlike a codec unit test, this exercises the system document pickers.
final class EncryptedFilesRoundtripUITests: XCTestCase {
#if APL_RUN_EXPLICIT_FILES_QA
    // Deliberately excluded from normal test discovery. Apple File Provider
    // sheets on iOS 27 can be presented from a separate process; an
    // unreliable coordinate tap must never make ordinary CI report a false
    // claim of complete Files acceptance. Run only as explicit interactive QA.
    func testEncryptedFileCanBeSavedAndReimported() throws {
#if !targetEnvironment(simulator)
        throw XCTSkip("Files acceptance uses a disposable simulator, never existing device credentials")
#else
        let app = XCUIApplication()
        let backupPass = "qaBackup2026Safe"
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru",
                                "-aplBackupFilesQA"]
        app.launch()
        let profilesTab = app.tabBars.buttons["Профили"]
        XCTAssertTrue(profilesTab.waitForExistence(timeout: 20))
        profilesTab.tap()

        // Profile must come from simulator-only fixture. This UI gate
        // covers Files and encryption, not the previously accepted importer.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "Synthetic Files QA"
        )).firstMatch.waitForExistence(timeout: 10), "Synthetic QA profile must exist")

        let backup = app.buttons["profiles.encryptedBackup"]
        XCTAssertTrue(backup.waitForExistence(timeout: 15))
        backup.tap()
        let exportSecret = app.secureTextFields["backup.export.password"]
        XCTAssertTrue(exportSecret.waitForExistence(timeout: 15))
        exportSecret.tap()
        exportSecret.typeText(backupPass)
        let confirm = app.secureTextFields.element(boundBy: 1)
        XCTAssertTrue(confirm.exists)
        confirm.tap()
        confirm.typeText(backupPass)
        let export = app.buttons["backup.export.create"]
        let length1 = (exportSecret.value as? String ?? "").count
        let length2 = (confirm.value as? String ?? "").count
        XCTAssertTrue(export.isEnabled,
                      "Synthetic backup export disabled; secure field lengths \(length1)/\(length2), check profile import and keyboard")
        export.tap()

        // iOS 27's Save to Files picker is an embedded remote document UI.
        // Its button is named 'Save' even when APL's own strings are Russian.
        let systemSave = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        let saveButton = app.buttons["Save"].firstMatch.exists
            ? app.buttons["Save"].firstMatch
            : systemSave.buttons["Save"].firstMatch
        if saveButton.waitForExistence(timeout: 5) {
            saveButton.tap()
        } else {
            // iOS 27 exposes the export picker via a remote UI service whose
            // Save control may not be included in the app XCUI hierarchy.
            // This is limited to the disposable simulator, not the user's phone.
            // iOS 27 remote document UI: Save is at x≈0.87, y≈0.11 of
            // the whole window, not y≈0.045 (which hits the status bar).
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.11)).tap()
        }
        XCTAssertTrue(app.staticTexts["Зашифрованная копия сохранена"].waitForExistence(timeout: 15))

        app.buttons["Выбрать файл .aplbackup"].tap()
        let document = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@", "APL-Profiles-Encrypted"
        )).firstMatch
        let restoreSecret = app.secureTextFields["backup.import.password"]
        if document.waitForExistence(timeout: 4) {
            document.tap()
        } else {
            // The iOS 27 remote Files provider often indexes freshly exported
            // files under Browse → On My iPhone, but not in Recents. The only
            // files present in this dedicated simulator's local provider are
            // QA-generated .aplbackup documents for this exact test password.
            // Never run the coordinate fallback on a physical device.
            Thread.sleep(forTimeInterval: 2)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.73, dy: 0.95)).tap()
            Thread.sleep(forTimeInterval: 1.5)
            // Two observed remote provider states: already inside On My
            // iPhone with the QA file tiles, or Browse root with a location
            // row at the same x/y. Attempt once, and only then choose tile.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.40)).tap()
            if !restoreSecret.waitForExistence(timeout: 2) {
                Thread.sleep(forTimeInterval: 1)
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.33)).tap()
            }
        }
        XCTAssertTrue(restoreSecret.waitForExistence(timeout: 10),
                      "Selected synthetic .aplbackup must be returned by Files before any decryption")
        restoreSecret.tap()
        restoreSecret.typeText(backupPass)
        app.buttons["backup.import.restore"].tap()
        // The same synthetic profile already exists: idempotence is a safety
        // property. This proves the selected Files document was decrypted.
        XCTAssertTrue(app.staticTexts["Добавлено профилей: 0"].waitForExistence(timeout: 15))
#endif
    }
    /// Purely synthetic, optional UI diagnostic: does NOT import or restore
    /// any file. Snapshots the system Files provider Browse navigation.
    func testInspectDisposableFilesBrowseNavigation() throws {
#if !targetEnvironment(simulator)
        throw XCTSkip("Never use the owner's physical phone for Files diagnostic")
#else
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES",
                                "-appLanguage.v1", "ru", "-aplBackupFilesQA"]
        app.launch()
        let tab = app.tabBars.buttons["Профили"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        let backup = app.buttons["profiles.encryptedBackup"]
        XCTAssertTrue(backup.waitForExistence(timeout: 10))
        backup.tap()
        let choose = app.buttons["Выбрать файл .aplbackup"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        choose.tap()
        Thread.sleep(forTimeInterval: 2)
        func capture(_ label: String) {
            let artifact = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            artifact.name = label
            artifact.lifetime = .keepAlways
            add(artifact)
        }
        capture("APL-Files-Recents-Before-Browse")

        // In iOS 27 the Files sheet may be a remote process and may not
        // expose its tab buttons in the app accessibility tree.
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        let browse = files.buttons["Обзор"].firstMatch.exists
            ? files.buttons["Обзор"].firstMatch : files.buttons["Browse"].firstMatch
        if browse.exists {
            browse.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.73, dy: 0.95)).tap()
        }
        Thread.sleep(forTimeInterval: 2)
        capture("APL-Files-After-First-Browse")
        // A controlled second attempt is diagnostic, never a fake PASS.
        if !files.staticTexts["На iPhone"].exists && !files.staticTexts["On My iPhone"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.73, dy: 0.91)).tap()
        }
        Thread.sleep(forTimeInterval: 1)
        capture("APL-Files-After-Second-Browse")
        let found = ["APL-Profiles-Encrypted", "На iPhone", "On My iPhone"]
            .map { name in
                [app, files].contains { target in
                    target.descendants(matching: .any).matching(
                        NSPredicate(format: "label CONTAINS %@", name)
                    ).firstMatch.exists
                }
            }
        print("APL_FILES_BROWSE_UI_MATCHED_DOCUMENT_\(found[0])_LOCATION_\(found[1] || found[2])")
#endif
    }

#endif // APL_RUN_EXPLICIT_FILES_QA
}
