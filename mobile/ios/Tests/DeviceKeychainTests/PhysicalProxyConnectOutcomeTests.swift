import Foundation
import NetworkExtension
import XCTest
@testable import Arvectum_Proxy_Launcher

/// Opt-in physical hardware CONNECT diagnosis; never part of the App Store
/// scheme, and never enables direct fallback, writes profiles or logs secrets.
final class PhysicalProxyConnectOutcomeTests: XCTestCase {
#if APL_RUN_EXPLICIT_VPN_QA
    func testBoundedRealPacketTunnelIPv4OnlyNativeConnectOutcome() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Requires authorized real iPhone with existing APL VPN")
#else
        let managers: [NETunnelProviderManager] = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { list, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: list ?? []) }
            }
        }
        let own = managers.filter {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == "ru.arvectum.proxylauncher.ios.PacketTunnel"
        }
        guard let manager = own.first(where: { $0.isEnabled }),
              manager.connection.status == .disconnected,
              let tunnel = manager.connection as? NETunnelProviderSession else {
            throw XCTSkip("Owner APL VPN must be installed and OFF")
        }
        var started = false
        var stopJob: DispatchWorkItem?
        defer {
            stopJob?.cancel()
            if started { tunnel.stopVPNTunnel() }
        }
        started = true
        try tunnel.startTunnel(options: [
            "requestedByUser": NSNumber(value: true),
            "qaStopAfterSeconds": NSNumber(value: 25),
            "qaTracePublicIPv4Only": NSNumber(value: true)
        ])
        let stopper = DispatchWorkItem { tunnel.stopVPNTunnel() }
        stopJob = stopper
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 20, execute: stopper
        )
        var connected = false
        for attempt in 0..<48 {
            let state = tunnel.status
            if state == .connected { connected = true; break }
            if state == .invalid || (state == .disconnected && attempt >= 16) { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard connected else {
            XCTFail("Bounded owner VPN did not reach Connected")
            return
        }
        print("APL_IPV4_FLOW_QA_SYSTEM_VPN_CONNECTED_GUARDED")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 7
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let client = URLSession(configuration: config)
        defer { client.invalidateAndCancel() }
        do {
            let request = URLRequest(url: URL(string: "https://ipv4.icanhazip.com")!)
            let (_, response) = try await client.data(for: request)
            print("APL_IPV4_FLOW_QA_URLSESSION_HTTP200_\((response as? HTTPURLResponse)?.statusCode == 200)")
        } catch {
            // NSError integer alone: never stringify an error, proxy URL,
            // hostname, DNS answer, username or Keychain value.
            print("APL_IPV4_FLOW_QA_URLSESSION_ERROR_CODE_\((error as NSError).code)")
        }

        stopJob?.cancel()
        tunnel.stopVPNTunnel()
        var off = false
        for _ in 0..<40 {
            if tunnel.status == .disconnected { off = true; break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertTrue(off, "System VPN must restore OFF after CONNECT diagnosis")
        if off { print("APL_IPV4_FLOW_QA_SYSTEM_VPN_EXPLICIT_OFF") }

        // New Debug-only event type contains only anonymous event code. The
        // telemetry ring may also contain normal profile names: NEVER print
        // the whole ring, only the filtered synthetic code counts.
        let events = TelemetryStore().list(limit: 40).filter {
            $0.type == "qa ipv4-only proxy connect outcome"
        }
        for code in 0...4 {
            let count = events.filter { $0.detail == "native_code=\(code)" }.count
            print("APL_IPV4_FLOW_QA_NATIVE_CONNECT_CODE_\(code)_COUNT_\(count)")
        }
        print("APL_IPV4_FLOW_QA_ANONYMOUS_EVENT_TOTAL_\(events.count)")
#endif
    }
#endif
}
