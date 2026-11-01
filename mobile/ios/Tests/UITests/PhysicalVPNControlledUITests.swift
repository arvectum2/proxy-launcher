import Foundation
import XCTest

/// Deliberately opt-in. The test uses the current user's existing proxy but
/// never inspects its credentials, creates a profile or changes selections.
/// Device traffic may be interrupted briefly. Two DEBUG-only timers in app
/// and packet-tunnel extension restore OFF even if XCTest loses wireless.
final class PhysicalVPNControlledUITests: XCTestCase {
#if APL_RUN_EXPLICIT_VPN_QA
    @MainActor
    private func dismissLowBatteryInterruption() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts["Низкий заряд"]
        guard alert.exists else { return }
        let close = alert.buttons["Закрыть"]
        if close.exists {
            close.tap()
            print("APL_PHYSICAL_QA dismissed_system_low_battery_alert=true")
        }
    }

    @MainActor
    func testTemporaryTunnelConnectAndRealHTTPS() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("System Packet Tunnel VPN acceptance requires an explicitly authorized physical iPhone")
#else
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES",
                                "-appLanguage.v1", "ru",
                                "-aplEphemeralTunnelQA"]
        app.launch()
        dismissLowBatteryInterruption()
        XCTAssertTrue(app.tabBars.buttons["Домой"].waitForExistence(timeout: 15))
        // Check the three compact primary actions before starting a bounded
        // live VPN test; no profiles or preferences are modified here.
        app.tabBars.buttons["Профили"].tap()
        XCTAssertTrue(app.buttons["profiles.import"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["profiles.encryptedBackup"].exists)
        let profileScreenshot = XCTAttachment(screenshot: app.screenshot())
        profileScreenshot.name = "APL 0.2 compact profile actions"
        profileScreenshot.lifetime = .keepAlways
        add(profileScreenshot)
        app.tabBars.buttons["Домой"].tap()
        dismissLowBatteryInterruption()
        let off = app.staticTexts["Отключено"]
        guard off.waitForExistence(timeout: 10) else {
            throw XCTSkip("Existing device VPN is not explicitly OFF; do not interrupt it")
        }
        let connect = app.buttons["Подключиться"]
        guard connect.waitForExistence(timeout: 3) else {
            throw XCTSkip("No manual working proxy or VPN Connect action is available")
        }
        connect.tap()
        defer {
            // Explicit cleanup in addition to independent 20/25 sec watchdogs.
            let disconnect = app.buttons["Отключить"]
            if disconnect.exists { disconnect.tap() }
        }
        guard app.staticTexts["Подключено"].waitForExistence(timeout: 12) else {
            throw XCTSkip("No working device proxy/tunnel authorization for a controlled VPN acceptance run")
        }
        // The system VPN is on at this point. Verify an actual remote HTTPS
        // request from a different iPhone process, not a simulated status.
        let request = URLRequest(url: URL(string: "https://example.com/")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 5)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200,
                           "Live HTTPS must succeed while the VPN is active")
        } catch {
            XCTFail("Temporary VPN was active, but the external HTTPS probe failed")
        }
        let disconnect = app.buttons["Отключить"]
        if disconnect.exists { disconnect.tap() }
        XCTAssertTrue(off.waitForExistence(timeout: 12), "VPN failed to restore OFF state")
#endif
    }
#endif
}
