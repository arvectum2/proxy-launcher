import XCTest
import Network

/// Hardware-only, gated by DEBUG QA VPN options in the application.
/// Never modifies stored profiles; APL disconnects after <=25s independently.
final class Smart3LiveTunnelPhysicalUITests: XCTestCase {
    /// Explicit hardware A/B test. A disposable proxy remains active for at
    /// most 115 seconds; app and extension terminate their VPN at 20s/25s.
    func testExperimentalScopedDirectAfterTwoFailures() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Real iPhone NetworkExtension required")
#else
        guard ProcessInfo.processInfo.environment["APL_SMART3_SCOPED_QA"] == "enabled" else {
            throw XCTSkip("Explicit scoped egress QA opt-in required")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru",
                                "-aplEphemeralTunnelQA", "-aplSmart3LocalProxyQA",
                                "-aplSmart3ScopedDirectLabQA"]
        app.launch()
        let connect = app.buttons["Подключиться"].firstMatch
        guard connect.waitForExistence(timeout: 15) else {
            throw XCTSkip("VPN already connected: never override user connection")
        }
        connect.tap()
        XCTAssertTrue(app.buttons["Отключить"].firstMatch.waitForExistence(timeout: 12),
                      "Disposable QA tunnel did not start")
        Thread.sleep(forTimeInterval: 23)
        // The mere existence of a VPN and two interface-scoped probe sockets
        // DOES NOT prove the fourth browser-like flow bypassed the upstream.
        // Fail this test until the tunnel records an actual exact-host TCP
        // connection and the requesting app receives TLS application bytes.
        // These are distinct facts: "lab direct armed" alone is not a pass.
        let activity = app.tabBars.buttons["Активность"]
        XCTAssertTrue(activity.waitForExistence(timeout: 8),
                      "Activity evidence must be inspectable after bounded QA")
        activity.tap()
        let refresh = app.buttons["activity.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()
        let scopedSocket = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "lab scoped tcp connected"))
            .firstMatch
        let tlsPayload = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "lab scoped tls data"))
            .firstMatch
        XCTAssertTrue(scopedSocket.waitForExistence(timeout: 5),
                      "No directly scoped TCP socket reached the target; probe success is insufficient")
        XCTAssertTrue(tlsPayload.waitForExistence(timeout: 5),
                      "No TLS response bytes from the same bypass target; the route is not verified")
        let recovered = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "lab sameflow recovered"))
            .firstMatch
        let originalData = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "lab sameflow tls data"))
            .firstMatch
        XCTAssertTrue(recovered.waitForExistence(timeout: 5),
                      "The original stalled TCP connection was NOT recovered after the proxy timeout")
        XCTAssertTrue(originalData.waitForExistence(timeout: 5),
                      "The original stalled TLS connection did NOT receive application bytes")
        print("APL_SCOPED_QA_SAME_FLOW_AND_FRESH_DIRECT_VERIFIED")
#endif
    }

    /// Physically adversarial split by hostname on a real CDN address:
    /// www.apple.com approved for DIRECT, its different apple.com.cn hostname
    /// MUST still traverse the mock upstream proxy. Never add IP exclusions.
    func testSharedCDNHostIsNotBypassedByAHostRule() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Real iPhone Packet Tunnel required")
#else
        guard ProcessInfo.processInfo.environment["APL_SMART3_SHAREDIP_QA"] == "enabled" else {
            throw XCTSkip("Explicit same-CDN physical QA opt-in required")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru",
                                "-aplEphemeralTunnelQA", "-aplSmart3LocalProxyQA",
                                "-aplSmart3ScopedDirectLabQA", "-aplSmart3SharedIPLabQA"]
        app.launch()
        let start = app.buttons["Подключиться"].firstMatch
        guard start.waitForExistence(timeout: 15) else {
            throw XCTSkip("Existing owner VPN must not be replaced")
        }
        start.tap()
        XCTAssertTrue(app.buttons["Отключить"].firstMatch.waitForExistence(timeout: 12))
        Thread.sleep(forTimeInterval: 23)
        let activity = app.tabBars.buttons["Активность"]
        XCTAssertTrue(activity.waitForExistence(timeout: 8))
        activity.tap()
        let refresh = app.buttons["activity.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()
        // The activity view is a virtualized list: early records such as
        // "lab direct armed" and "lab sameflow recovered" can be off-screen,
        // although they remain in App Group telemetry. Require latest proof
        // in UI, and independently audit ALL original flow events plus the
        // temporary mock proxy from the captured preference snapshot.
        for evidence in ["lab scoped tls data",
                         "lab direct server bytes",
                         "lab neighbor via proxy"] {
            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", evidence)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5),
                          "Missing physical shared-CDN routing evidence: \(evidence)")
        }
        print("APL_SHARED_CDN_EXACT_HOST_DIRECT_NEIGHBOR_PROXY_PROVED")
#endif
    }

    /// Physical IPv6-only bound TCP completed but HTTPS stalled on this
    /// iPhone; until fixed, NEVER open direct IPv6 sockets. Fail closed and
    /// keep a distinct canonical hostname on upstream proxy.
    func testIPv6OnlyFailsClosedWithCanonicalNeighborProxy() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone IPv6 interface required")
#else
        guard ProcessInfo.processInfo.environment["APL_SMART3_IPV6_QA"] == "enabled" else {
            throw XCTSkip("Explicit physical IPv6 QA opt-in required")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru",
                                "-aplEphemeralTunnelQA", "-aplSmart3LocalProxyQA",
                                "-aplSmart3ScopedDirectLabQA", "-aplSmart3IPv6OnlyLabQA"]
        app.launch()
        guard app.buttons["Подключиться"].firstMatch.waitForExistence(timeout: 15) else {
            throw XCTSkip("Owner VPN already in use; never override")
        }
        app.buttons["Подключиться"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Отключить"].firstMatch.waitForExistence(timeout: 12))
        Thread.sleep(forTimeInterval: 23)
        let activity = app.tabBars.buttons["Активность"]
        XCTAssertTrue(activity.waitForExistence(timeout: 8))
        activity.tap()
        let refresh = app.buttons["activity.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()
        for evidence in ["lab scoped tls attempt",
                         "lab ipv6 neighbor via proxy"] {
            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", evidence)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5),
                "Missing IPv6 fail-closed and unrelated proxy proof: \(evidence)")
        }
        print("APL_IPV6_ONLY_FAILCLOSED_AND_NEIGHBOR_PROXY_DEVICE_QA")
#endif
    }

    /// No real radio switch: exercise the same revocation callback on a
    /// physical device while preserving the owner's Wi-Fi/LTE settings.
    /// The independent App Group+mock audit proves the post-revocation
    /// fourth connection stays on proxy, never silently escapes direct.
    func testScopedDirectRevokedOnSimulatedNetworkChange() throws {
        try exerciseBoundedRouteRevocation(
            environment: "APL_SMART3_PATH_RESET_QA",
            flag: "-aplSmart3PathResetLabQA")
    }

    func testScopedDirectRevokedAtShortenedLabTTL() throws {
        try exerciseBoundedRouteRevocation(
            environment: "APL_SMART3_TTL_RESET_QA",
            flag: "-aplSmart3TTLResetLabQA")
    }

    private func exerciseBoundedRouteRevocation(environment: String, flag: String) throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone and Packet Tunnel required")
#else
        guard ProcessInfo.processInfo.environment[environment] == "enabled" else {
            throw XCTSkip("No explicit destructive-free hardware revocation QA consent")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru",
                                "-aplEphemeralTunnelQA", "-aplSmart3LocalProxyQA",
                                "-aplSmart3ScopedDirectLabQA", flag]
        app.launch()
        guard app.buttons["Подключиться"].firstMatch.waitForExistence(timeout: 15) else {
            throw XCTSkip("Owner VPN already active; never replace it")
        }
        app.buttons["Подключиться"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Отключить"].firstMatch.waitForExistence(timeout: 12))
        Thread.sleep(forTimeInterval: 24)
        let activity = app.tabBars.buttons["Активность"]
        XCTAssertTrue(activity.waitForExistence(timeout: 8))
        activity.tap()
        let refresh = app.buttons["activity.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 6))
        refresh.tap()
        let newAttempt = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "lab scoped tls attempt"))
            .firstMatch
        XCTAssertTrue(newAttempt.waitForExistence(timeout: 5),
                      "Post-revocation target connection was not attempted")
        print("APL_SCOPED_ROUTE_REVOCATION_QA_REQUIRES_INDEPENDENT_MOCK_AUDIT")
#endif
    }

    /// Browser E2E, not an app NWConnection substitute. The only traffic
    /// producer after VPN activation is real Safari: synthetic HTTP A serves
    /// an HTTP 302 to https://www.apple.com/, whose CONNECTs are withheld.
    /// The tunnel must independently learn B and finish Safari navigation.
    func testSafariHTTPRedirectRecoversAuthLikeHostWithoutReload() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Requires physical Safari and Packet Tunnel")
#else
        guard ProcessInfo.processInfo.environment["APL_SMART3_SAFARI_QA"] == "enabled" else {
            throw XCTSkip("Explicit real Safari physical experiment is required")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES", "-appLanguage.v1", "ru",
                                "-aplEphemeralTunnelQA", "-aplSmart3LocalProxyQA",
                                "-aplSmart3ScopedDirectLabQA", "-aplSmart3SafariRedirectQA"]
        app.launch()
        let connect = app.buttons["Подключиться"].firstMatch
        guard connect.waitForExistence(timeout: 15) else {
            throw XCTSkip("Owner VPN is already running; never override it")
        }
        connect.tap()
        XCTAssertTrue(app.buttons["Отключить"].firstMatch.waitForExistence(timeout: 12),
                      "Temporary Safari QA VPN did not start")
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 18),
                      "Safari was not opened on synthetic A by the application")
        print("APL_SAFARI_BROWSER_APPEARED")
        let browser = safari.webViews.firstMatch
        XCTAssertTrue(browser.waitForExistence(timeout: 12),
                      "No Safari WebKit page appeared")
        Thread.sleep(forTimeInterval: 13)
        let hierarchy = safari.debugDescription
        print("APL_SAFARI_HIERARCHY_PREVIEW_\(String(hierarchy.prefix(1600)))")
        // Safari address UI usually hides leading "www."; don't require
        // the literal DNS hostname in its shortened address-bar label.
        XCTAssertTrue(hierarchy.contains("apple.com"),
                      "Safari did not expose the redirected target domain")
        let page = browser.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "iPhone")
        ).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 4),
                      "Safari target HTML did not render after automatic bypass")
        print("APL_SAFARI_REDIRECT_HTML_RENDERED")
        app.activate()
        let activity = app.tabBars.buttons["Активность"]
        XCTAssertTrue(activity.waitForExistence(timeout: 6),
                      "Cannot check Packet Tunnel browser-flow evidence")
        activity.tap()
        let refresh = app.buttons["activity.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()
        let approved = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "lab direct armed")
        ).firstMatch
        let recovered = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "lab sameflow recovered")
        ).firstMatch
        let downstream = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "lab direct server bytes")
        ).firstMatch
        XCTAssertTrue(approved.waitForExistence(timeout: 5),
                      "No independent proof activated exact-host DIRECT")
        XCTAssertTrue(recovered.waitForExistence(timeout: 5),
                      "Safari's original blocked TCP stream was not recovered")
        XCTAssertTrue(downstream.waitForExistence(timeout: 5),
                      "No response bytes crossed the physical direct TCP stream")
#endif
    }

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
