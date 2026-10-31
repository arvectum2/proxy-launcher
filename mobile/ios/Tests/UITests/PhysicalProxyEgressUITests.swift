import Foundation
import XCTest

/// Opt-in system VPN test: proves a public address change from an independent
/// iPhone process with the APL tunnel ON, then its restoration after OFF.
/// Raw public IPs (including the user's baseline) are never logged.
final class PhysicalProxyEgressUITests: XCTestCase {
#if APL_RUN_EXPLICIT_VPN_QA
    private struct PublicEgress: Equatable {
        let ipify: String
        let cloudflare: String
    }

    private enum EgressProbeError: Error {
        case invalidResponse
    }

    /// An ephemeral session avoids a stale cached IP response across VPN hops.
    /// Two independent HTTPS providers must agree on whether egress changed;
    /// their IP versions may differ, so do not compare providers to each other.
    private func sampleEgress() async throws -> PublicEgress {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        @Sendable func request(_ url: String) async throws -> String {
            var req = URLRequest(url: URL(string: url)!)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 4
            let (data, response) = try await session.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = String(data: data, encoding: .utf8),
                  body.utf8.count < 4000 else {
                throw EgressProbeError.invalidResponse
            }
            return body
        }

        async let ipifyBody = request("https://api.ipify.org")
        async let cloudflareBody = request("https://www.cloudflare.com/cdn-cgi/trace")
        let rawIpify = try await ipifyBody
        let rawCloudflare = try await cloudflareBody
        let publicIP = rawIpify.trimmingCharacters(in: .whitespacesAndNewlines)
        let traceIP = rawCloudflare.split(separator: "\n").first {
            $0.hasPrefix("ip=")
        }.map { String($0.dropFirst(3)) } ?? ""
        guard !publicIP.isEmpty, !traceIP.isEmpty,
              !publicIP.contains(" "), !traceIP.contains(" "),
              publicIP.count < 48, traceIP.count < 48 else {
            throw EgressProbeError.invalidResponse
        }
        return PublicEgress(ipify: publicIP, cloudflare: traceIP)
    }

    @MainActor
    func testVPNChangesPublicEgressAndRestoresBaseline() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("A real public VPN egress comparison is physical-iPhone only")
#else
        let app = XCUIApplication()
        app.launchArguments += ["-privacyDisclosureAccepted.v1", "YES",
                                "-setupGuideSeen.v1", "YES",
                                "-appLanguage.v1", "ru",
                                "-aplEphemeralTunnelQA"]
        app.launch()
        guard app.tabBars.buttons["Главная"].waitForExistence(timeout: 12),
              app.staticTexts["Отключено"].waitForExistence(timeout: 7) else {
            throw XCTSkip("APL was not confirmed OFF; no VPN state will be changed")
        }
        let before: PublicEgress
        do {
            before = try await sampleEgress()
        } catch {
            throw XCTSkip("Both public egress providers must be reachable before enabling VPN")
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let stableBaseline: PublicEgress
        do {
            stableBaseline = try await sampleEgress()
        } catch {
            throw XCTSkip("Public IP services became unavailable before VPN activation")
        }
        guard before == stableBaseline else {
            throw XCTSkip("Public baseline was volatile while APL VPN was OFF; cannot attest egress change reliably")
        }
        print("APL_EGRESS preflight=2_services_valid baseline_stable=true raw_addresses=redacted")

        let connect = app.buttons["Подключиться"]
        guard connect.waitForExistence(timeout: 3) else {
            throw XCTSkip("No safe Connect action exists on this device")
        }
        connect.tap()
        defer {
            // Extra cleanup alongside DEBUG app and extension timers (20s/25s).
            let disconnect = app.buttons["Отключить"]
            if disconnect.exists { disconnect.tap() }
        }
        guard app.staticTexts["Подключено"].waitForExistence(timeout: 14) else {
            let possibleStates = ["Отключено", "Подключение…", "Отключение…", "Переподключение…"]
            let visible = possibleStates.first(where: { app.staticTexts[$0].exists }) ?? "unrecognized"
            let hasAlert = app.alerts.firstMatch.exists
            print("APL_EGRESS connect_timeout state=\(visible) alert_present=\(hasAlert) raw_addresses=redacted")
            XCTFail("APL tunnel did not reach Connected within 14 seconds; recorded sanitized status")
            return
        }
        let during: PublicEgress
        do {
            during = try await sampleEgress()
        } catch {
            XCTFail("Both HTTPS egress providers must be reachable with the VPN enabled")
            return
        }
        let changed = (before.ipify != during.ipify ? 1 : 0) +
                      (before.cloudflare != during.cloudflare ? 1 : 0)
        print("APL_EGRESS vpn_connected=true providers_checked=2 providers_changed=\(changed) raw_addresses=redacted")

        let disconnect = app.buttons["Отключить"]
        if disconnect.exists { disconnect.tap() }
        guard app.staticTexts["Отключено"].waitForExistence(timeout: 12) else {
            XCTFail("APL did not visibly return to OFF after explicit disconnect")
            return
        }
        var restored = 0
        // iOS may tear down the VPN route before its default IPv4/IPv6 paths
        // have fully converged. Retry only with APL visibly OFF; no new VPN ON.
        for attempt in 1...4 {
            let after: PublicEgress
            do {
                after = try await sampleEgress()
            } catch {
                if attempt == 4 {
                    XCTFail("Public IP services remained unreachable after VPN disconnect")
                    return
                }
                try await Task.sleep(nanoseconds: 1_200_000_000)
                continue
            }
            let ipifyRestored = before.ipify == after.ipify
            let cloudflareRestored = before.cloudflare == after.cloudflare
            restored = (ipifyRestored ? 1 : 0) + (cloudflareRestored ? 1 : 0)
            print("APL_EGRESS post_attempt=\(attempt) ipify_restored=\(ipifyRestored) cloudflare_restored=\(cloudflareRestored) raw_addresses=redacted")
            if restored == 2 { break }
            if attempt < 4 { try await Task.sleep(nanoseconds: 1_200_000_000) }
        }
        XCTAssertTrue(changed == 2,
                      "Both independent providers must detect a VPN egress change")
        XCTAssertTrue(restored == 2,
                      "Direct public egress must return to baseline within four OFF-only samples")
#endif
    }
#endif
}
