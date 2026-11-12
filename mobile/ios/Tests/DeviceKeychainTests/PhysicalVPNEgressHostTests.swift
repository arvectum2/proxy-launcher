import Foundation
import NetworkExtension
import XCTest
@testable import Arvectum_Proxy_Launcher

/// Explicitly opt-in physical hardware QA. The real signed app hosts this
/// test, but the tunnel has independent host (20s) and extension (25s) stop
/// guards. No user profiles, secrets, preferences or IDs are logged.
final class PhysicalVPNEgressHostTests: XCTestCase {
#if APL_RUN_EXPLICIT_VPN_QA
    private struct Egress: Equatable {
        let ipify: String
        let cloudflare: String
    }
    private enum ReceiptError: Error { case invalid }

    private func egress() async throws -> Egress {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        config.urlCache = nil
        let client = URLSession(configuration: config)
        defer { client.invalidateAndCancel() }

        @Sendable func fetch(_ address: String) async throws -> String {
            guard let url = URL(string: address) else { throw ReceiptError.invalid }
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 4
            let (bytes, response) = try await client.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  bytes.count < 4096, let string = String(data: bytes, encoding: .utf8)
            else { throw ReceiptError.invalid }
            return string
        }
        async let first = fetch("https://api.ipify.org")
        async let second = fetch("https://www.cloudflare.com/cdn-cgi/trace")
        let firstResult = try await first
        let secondResult = try await second
        let ip = firstResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let traceIP = secondResult.split(separator: "\n")
            .first(where: { $0.hasPrefix("ip=") })
            .map { String($0.dropFirst(3)) } ?? ""
        guard (3..<48).contains(ip.count), (3..<48).contains(traceIP.count),
              !ip.contains(" "), !traceIP.contains(" ")
        else { throw ReceiptError.invalid }
        return Egress(ipify: ip, cloudflare: traceIP)
    }

    private func existingOffTunnel() async throws -> NETunnelProviderSession {
        let managers: [NETunnelProviderManager] = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { list, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: list ?? []) }
            }
        }
        let ourManagers = managers.filter {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == "ru.arvectum.proxylauncher.ios.PacketTunnel"
        }
        guard let manager = ourManagers.first(where: { $0.isEnabled }),
              manager.connection.status == .disconnected,
              let session = manager.connection as? NETunnelProviderSession
        else { throw XCTSkip("APL VPN must be installed, enabled and already OFF") }
        return session
    }

    func testBoundedAPLPacketTunnelChangesAndRestoresPublicEgress() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Real PacketTunnel test requires specifically authorized iPhone")
#else
        let session = try await existingOffTunnel()
        let before: Egress
        do {
            before = try await egress()
            let check = try await egress()
            guard before == check else {
                throw XCTSkip("Public IP baseline volatile, no VPN activation")
            }
        } catch {
            throw XCTSkip("Public IP witness unavailable while VPN OFF")
        }
        print("APL_VPN_030_PREFLIGHT_OFF_STABLE_TWO_ORIGIN_SERVICES")

        // Guard #1: host timer calls stop at 20s. Guard #2: the PacketTunnel
        // itself cancels after 25s even if the host process is killed.
        var attempted = false
        var stopItem: DispatchWorkItem?
        defer {
            stopItem?.cancel()
            if attempted { session.stopVPNTunnel() }
        }
        attempted = true
        do {
            try session.startTunnel(options: [
                "requestedByUser": NSNumber(value: true),
                "qaStopAfterSeconds": NSNumber(value: 25)
            ])
        } catch {
            XCTFail("System VPN start refused; no private error details logged")
            return
        }
        let safety = DispatchWorkItem { session.stopVPNTunnel() }
        stopItem = safety
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 20, execute: safety
        )

        var connected = false
        // startTunnel(options:) is asynchronous; the first status sample may
        // still be .disconnected before the NE session enters .connecting.
        // Never misclassify that initial transition as an immediate failure.
        for attempt in 0..<48 {
            let state = session.status
            if state == .connected { connected = true; break }
            if state == .invalid || (state == .disconnected && attempt >= 16) {
                break
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard connected else {
            XCTFail("PacketTunnel did not connect; bounded auto-stop armed")
            return
        }
        print("APL_VPN_030_CONNECTED_WITH_20S_AND_25S_STOP_GUARDS")

        let during: Egress
        do { during = try await egress() }
        catch {
            XCTFail("HTTPS witnesses unavailable while real VPN was connected")
            return
        }
        let changed = (during.ipify != before.ipify ? 1 : 0)
            + (during.cloudflare != before.cloudflare ? 1 : 0)
        print("APL_VPN_030_ORIGIN_PROVIDERS_CHANGED_\(changed)_OF_2")

        stopItem?.cancel()
        session.stopVPNTunnel()
        var off = false
        for _ in 0..<40 {
            if session.status == .disconnected { off = true; break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        guard off else {
            XCTFail("VPN not OFF within 8s; extension kill timer armed")
            return
        }
        print("APL_VPN_030_EXPLICIT_OFF_CONFIRMED")

        var restored = 0
        for attempt in 1...3 {
            do {
                let after = try await egress()
                restored = (after.ipify == before.ipify ? 1 : 0)
                    + (after.cloudflare == before.cloudflare ? 1 : 0)
                if restored == 2 { break }
            } catch {}
            if attempt < 3 { try await Task.sleep(nanoseconds: 850_000_000) }
        }
        print("APL_VPN_030_ORIGIN_PROVIDERS_RESTORED_\(restored)_OF_2")
        XCTAssertEqual(changed, 2, "System VPN must change both public IP witnesses")
        XCTAssertEqual(restored, 2, "VPN OFF must restore both direct IP witnesses")
#endif
    }
#endif
}
