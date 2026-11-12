import XCTest
@testable import Arvectum_Proxy_Launcher

/// Physical-device-only network QA. Exercises production ProxyProbe through
/// the actual saved profile and Keychain without touching NEPacketTunnelProvider.
/// Only anonymous profile indices and aggregate success count enter test logs.
final class PhysicalProxyHandshakeReadOnlyTests: XCTestCase {
    func testExistingProfilesCanNegotiateProxyTunnelWithoutEnablingVPN() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical owner device and existing authenticated profiles required")
        #else
        let store = try ProfileStore()
        let profiles = store.listProfiles()
        XCTAssertEqual(profiles.count, 3, "Expected existing three profiles after upgrade")

        let probe = ProxyProbe()
        var succeeded = 0
        for (index, profile) in profiles.enumerated() {
            // Keychain data stays in this process. Never print the raw Error:
            // diagnostics may contain a remote hostname, username or token.
            guard let password = try store.password(for: profile.id),
                  !password.isEmpty else {
                XCTFail("Profile index \(index + 1) has no saved Keychain secret")
                continue
            }
            do {
                // Existing production probe authenticates to the configured
                // HTTP(S) CONNECT / SOCKS5 server and tries example.com:443.
                // This does NOT verify end-to-end HTTPS or VPN TUN routing.
                let result = try await probe.resolveMeasured(profile, password: password)
                XCTAssertNotEqual(result.profile.type, .auto)
                XCTAssertGreaterThan(result.latencyMs, 0)
                succeeded += 1
                print("APL_PROXY_QA_INDEX_\(index + 1)_CONNECT_PASS")
            } catch {
                print("APL_PROXY_QA_INDEX_\(index + 1)_CONNECT_FAILED")
            }
        }
        print("APL_PROXY_QA_CONNECT_PASSED_\(succeeded)_OF_\(profiles.count)")
        XCTAssertGreaterThan(succeeded, 0, "No configured proxy completed CONNECT/SOCKS5 handshake")
        #endif
    }
}
