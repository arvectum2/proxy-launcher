import Foundation
import NetworkExtension
import XCTest
@testable import Arvectum_Proxy_Launcher

/// Reads APL's Network Extension state in the signed app process, without
/// creating/saving a VPN manager, starting a tunnel, or logging endpoints.
final class PhysicalVPNStatusReadOnlyTests: XCTestCase {
    func testAPLNetworkExtensionIsDisconnectedBeforeActiveQA() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires existing APL Network Extension on a physical iPhone")
        #else
        let managers: [NETunnelProviderManager] = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: managers ?? []) }
            }
        }
        let apl = managers.filter {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == "ru.arvectum.proxylauncher.ios.PacketTunnel"
        }
        XCTAssertFalse(apl.isEmpty, "Existing APL PacketTunnel preference must be present")
        for manager in apl {
            let status = manager.connection.status
            let isOff = status == .disconnected || status == .invalid
            if isOff { print("APL_VPN_QA_READONLY_OFF_CONFIRMED") }
            else { print("APL_VPN_QA_READONLY_UNEXPECTED_ACTIVE") }
            XCTAssertTrue(isOff, "APL VPN was not OFF; active tunnel QA prohibited")
        }
        #endif
    }
}
