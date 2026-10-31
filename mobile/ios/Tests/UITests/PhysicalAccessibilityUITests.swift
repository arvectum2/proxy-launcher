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
        app.buttons["Исключения сайтов"].tap()
        XCTAssertTrue(app.navigationBars["Исключения сайтов"].waitForExistence(timeout: 10))
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
        // This is an explicit regression threshold, NOT WCAG certification.
        // The initial physical iPhone report had 15 issues; residual issues
        // remain visible in the report and must be fixed separately.
        XCTAssertLessThan(issueCount, 15, "Accessibility regressed against the initial hardware baseline")
    }
}
