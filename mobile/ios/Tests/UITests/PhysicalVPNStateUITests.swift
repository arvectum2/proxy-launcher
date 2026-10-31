import XCTest

/// Read-only physical acceptance gate. Never changes the actual VPN state,
/// selected profile, stored credentials, or iOS device preferences.
final class PhysicalVPNStateUITests: XCTestCase {
    func testReportCurrentVPNReadinessWithoutToggling() {
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Главная"].waitForExistence(timeout: 20))
        let states = ["Подключено", "Отключено", "Подключение…", "Отключение…"]
        let found = states.first(where: { app.staticTexts[$0].exists }) ?? "not-ready"
        let noProfiles = app.staticTexts["Прокси пока нет"].exists
        print("APL_PHYSICAL_VPN_READONLY state=\(found) hasProfiles=\(!noProfiles)")
        XCTAssertNotEqual(found, "not-ready", "VPN status was not displayed in the home screen")
    }
}
