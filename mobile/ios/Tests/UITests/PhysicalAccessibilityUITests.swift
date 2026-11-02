import XCTest

@available(iOS 17.0, *)
final class PhysicalAccessibilityUITests: XCTestCase {
    func testSmartExclusionsAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let exclusionsButton = app.buttons["settings.siteExclusions"]
        // With physical VoiceOver enabled, a single tap may focus the element
        // instead of activating it. Double-tap only if navigation did not occur.
        // The same test continues to work with VoiceOver disabled.
        if !exclusionsButton.waitForExistence(timeout: 2) {
            settings.doubleTap()
        }
        XCTAssertTrue(exclusionsButton.waitForExistence(timeout: 10),
                      "Settings must be accessible with or without VoiceOver")
        exclusionsButton.tap()
        let exclusionsTitle = app.navigationBars["Исключения"]
        if !exclusionsTitle.waitForExistence(timeout: 2) {
            exclusionsButton.doubleTap()
        }
        XCTAssertTrue(exclusionsTitle.waitForExistence(timeout: 10),
                      "Site exclusions screen must be reachable by VoiceOver activation")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "APL Smart Exclusions physical baseline"
        attachment.lifetime = .keepAlways
        add(attachment)
        var issueCount = 0
        try app.performAccessibilityAudit { issue in
            issueCount += 1
            let raw = issue.element?.label ?? "(unlabeled)"
            let clean = raw.replacingOccurrences(of: #"[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+"#,
                                                 with: "[host]", options: .regularExpression)
            let frame = issue.element?.frame ?? .zero
            print("APL_A11Y_FINDING type=\(issue.auditType) label=\(String(clean.prefix(125))) frame=\(frame) detail=\(String(issue.compactDescription.prefix(140)))")
            return true // Triaging findings, NOT accepting/ignoring them for release.
        }
        print("APL_A11Y_FINDINGS_TOTAL=\(issueCount)")
        // All eight reproducible findings on this screen are fixed. Keep
        // zero as the strict gate; this is not general WCAG certification.
        XCTAssertEqual(issueCount, 0, "Smart Exclusions accessibility audit must remain clean")
    }
}
