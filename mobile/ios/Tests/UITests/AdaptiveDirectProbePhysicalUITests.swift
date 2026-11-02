import XCTest

/// Exercise the *app's* Network.framework TLS check on physical hardware.
/// Interface affinity does not prove this socket bypassed an active VPN.
final class AdaptiveDirectProbePhysicalUITests: XCTestCase {
    func testPhysicalTLSProbeDisplaysBoundedDiagnostic() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Physical path attribution needs hardware")
#else
        guard ProcessInfo.processInfo.environment["APL_SMART3_HARDWARE_QA"] == "enabled" else {
            throw XCTSkip("Requires explicit Smart3 hardware QA opt-in; do not disturb normal iPhone tests")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES",
                                "-appLanguage.v1", "ru", "-qaSmart3ProbeFixture", "YES"]
        app.launch()
        let settings = app.tabBars.buttons["Настройки"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let exclusions = app.buttons["Исключения сайтов"]
        XCTAssertTrue(exclusions.waitForExistence(timeout: 10))
        exclusions.tap()
        let host = app.staticTexts["www.apple.com"].firstMatch
        for _ in 0..<6 where !host.exists { app.swipeUp() }
        XCTAssertTrue(host.waitForExistence(timeout: 10))
        let readyWiFi = app.staticTexts["TLS через Wi-Fi доступен (маршрут не подтверждён)"].firstMatch
        let readyCell = app.staticTexts["TLS через мобильную сеть доступен (маршрут не подтверждён)"].firstMatch
        let failed = app.staticTexts["Проверка TLS не удалась"].firstMatch
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline && !readyWiFi.exists && !readyCell.exists && !failed.exists {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(readyWiFi.exists || readyCell.exists || failed.exists,
                      "Bounded physical TLS diagnosis must finish with explicit uncertainty: \(app.debugDescription)")
        XCTAssertFalse(app.buttons["Удалить исключение www.apple.com"].exists,
                       "TLS success may NEVER authorize a silent bypass")
#endif
    }
}
