import XCTest
import Network

/// Hardware-only, gated by DEBUG QA VPN options in the application.
/// Never modifies stored profiles; APL disconnects after <=25s independently.
final class Smart3LiveTunnelPhysicalUITests: XCTestCase {
    private func exercise(_ host: String) -> NWConnection {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: .https,
                                      using: .tcp)
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(content: Data("GET / HTTP/1.1\r\nHost: \(host)\r\n\r\n".utf8),
                                completion: .contentProcessed({ _ in }))
            }
        }
        connection.start(queue: DispatchQueue(label: "ru.arvectum.qa.\(host).\(UUID().uuidString)"))
        return connection
    }

    func testLiveVPTunnelPerHostCONNECTSignalWithAutoRollback() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Real Network Extension required")
#else
        guard ProcessInfo.processInfo.environment["APL_SMART3_HARDWARE_QA"] == "enabled" else {
            throw XCTSkip("Requires explicit Smart3 hardware QA opt-in; do not disturb normal iPhone tests")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES", "-setupGuideSeen.v1", "YES",
                                "-appLanguage.v1", "ru", "-aplEphemeralTunnelQA", "-aplSmart3LocalProxyQA"]
        app.launch()
        let connect = app.buttons["Подключиться"].firstMatch
        guard connect.waitForExistence(timeout: 13) else {
            throw XCTSkip("VPN already connected or screen not ready: avoid altering previous user tunnel")
        }
        connect.tap()
        // Core Network Extension may prompt for VPN permissions on first
        // install. The device already has an APL VPN configuration.
        let disconnect = app.buttons["Отключить"].firstMatch
        XCTAssertTrue(disconnect.waitForExistence(timeout: 10), "QA tunnel could not be activated")
        // Two distinct target TCP sessions in parallel, after a successful
        // CONNECT to a different host to show the upstream listener is alive.
        // Real physical iPhone check WHILE default route points to the APL
        // Packet Tunnel. A scoped connection that succeeds when the mock
        // upstream does not forward www.apple.com is independent evidence.
        let physicalProbe = await AdaptiveDirectProbe.checkTLS(host: "www.apple.com", timeout: 4)
        print("APL Smart3 scoped physical TLS while VPN connected: \(physicalProbe)")
        let healthy = exercise("probe.qa-example.test")
        Thread.sleep(forTimeInterval: 2)
        let blocked1 = exercise("auth.qa-example.test")
        let blocked2 = exercise("auth.qa-example.test")
        Thread.sleep(forTimeInterval: 15)
        healthy.cancel(); blocked1.cancel(); blocked2.cancel()
        // QA app kills at 20s and Packet Tunnel independently kills at 25s.
        // If host automation is interrupted, the extension safety timer still
        // terminates the VPN without relying on this runner.
        print("APL Smart3 live packet-tunnel probe completed; inspect test proxy and local flow evidence")
#endif
    }
}
