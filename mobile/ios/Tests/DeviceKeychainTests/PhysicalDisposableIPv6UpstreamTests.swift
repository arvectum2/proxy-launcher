import Darwin
import Foundation
import Network
import NetworkExtension
import XCTest
@testable import Arvectum_Proxy_Launcher

/// Physical-only signed Debug test. The temporary LAN HTTP CONNECT relay
/// reaches only a public IPv6-only destination, never owner saved profiles.
final class PhysicalDisposableIPv6UpstreamTests: XCTestCase {
#if APL_RUN_EXPLICIT_VPN_QA
    private enum WitnessError: Error { case invalid }

    @available(iOS 17.0, *)
    private func ipv6Witness(_ source: ProxyConfiguration?) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 7
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        if let source { config.proxyConfigurations = [source] }
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://v6.ident.me")!)
        let (body, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              body.count < 128,
              let raw = String(data: body, encoding: .utf8) else {
            throw WitnessError.invalid
        }
        let origin = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var ip = in6_addr()
        guard origin.withCString({ inet_pton(AF_INET6, $0, &ip) == 1 }) else {
            throw WitnessError.invalid
        }
        return origin // In-process equality only; do not log/persist client IP.
    }

    private func existingOffTunnel() async throws -> NETunnelProviderSession {
        let managers: [NETunnelProviderManager] = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { list, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: list ?? []) }
            }
        }
        guard let manager = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == "ru.arvectum.proxylauncher.ios.PacketTunnel" && $0.isEnabled
        }), manager.connection.status == .disconnected,
              let tunnel = manager.connection as? NETunnelProviderSession else {
            throw XCTSkip("Owner APL VPN must be installed, enabled and OFF")
        }
        return tunnel
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        func run(_ callback: () -> Void) {
            lock.lock()
            let shouldFinish = !finished
            finished = true
            lock.unlock()
            if shouldFinish { callback() }
        }
    }

    /// Probe literal public IPv6 TCP/TLS with explicit certificate hostname.
    /// Unlike VirtualDNS fake IPv4 for DNS names, this sends a native IPv6
    /// destination packet into Network Extension's ::/0 routes.
    private func nativeIPv6TLS() async -> Bool {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, "one.one.one.one")
        let destination = NWEndpoint.Host.ipv6(IPv6Address("2606:4700:4700::1111")!)
        let connection = NWConnection(
            host: destination, port: NWEndpoint.Port(rawValue: 443)!,
            using: NWParameters(tls: tls))
        let once = Once()
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let finish: (Bool) -> Void = { success in
                once.run {
                    connection.cancel()
                    cont.resume(returning: success)
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = Data(
                        "GET /cdn-cgi/trace HTTP/1.1\r\nHost: one.one.one.one\r\nConnection: close\r\n\r\n".utf8)
                    connection.send(content: request, completion: .contentProcessed { error in
                        if error != nil { finish(false); return }
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
                            data, _, _, error in
                            guard error == nil, let data,
                                  let status = String(data: data, encoding: .utf8) else {
                                finish(false); return
                            }
                            finish(status.hasPrefix("HTTP/1.1 200"))
                        }
                    })
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue(label: "ru.arvectum.apl.ipv6-qa-native-tls"))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + 6) { finish(false) }
        }
    }

    func testBoundedPacketTunnelIPv6OnlyDestinationViaDisposableUpstream() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Requires authorized physical iPhone and disposable IPv6 upstream")
#else
        guard #available(iOS 17.0, *) else { throw XCTSkip("ProxyConfiguration requires iOS17+") }
        let tunnel = try await existingOffTunnel()
        let before: String
        do {
            before = try await ipv6Witness(nil)
            let second = try await ipv6Witness(nil)
            guard before == second else { throw XCTSkip("Direct IPv6 baseline volatile") }
        } catch {
            throw XCTSkip("Direct native IPv6 witness unavailable; VPN not activated")
        }
        print("APL_V6_LAB_DIRECT_IPV6_ONLY_HTTPS_STABLE_OFF")
        let local = NWEndpoint.hostPort(
            host: .init("192.168.1.80"), port: NWEndpoint.Port(rawValue: 18081)!)
        var disposable = ProxyConfiguration(httpCONNECTProxy: local)
        disposable.allowFailover = false
        let control: String
        do { control = try await ipv6Witness(disposable) }
        catch { throw XCTSkip("Disposable IPv6 proxy preflight failed; VPN untouched") }
        guard control != before else {
            throw XCTSkip("Disposable upstream not independent from direct path")
        }
        print("APL_V6_LAB_DISPOSABLE_CONNECT_IPV6_ONLY_PASS_CHANGED_true")

        var started = false
        var stopJob: DispatchWorkItem?
        defer {
            stopJob?.cancel()
            if started { tunnel.stopVPNTunnel() }
        }
        started = true
        do {
            try tunnel.startTunnel(options: [
                "requestedByUser": NSNumber(value: true),
                "qaStopAfterSeconds": NSNumber(value: 25),
                "qaSmart3ProxyHost": "192.168.1.80" as NSString,
                "qaSmart3ProxyPort": NSNumber(value: 18081)
            ])
        } catch {
            XCTFail("Bounded disposable PacketTunnel start was rejected")
            return
        }
        let stop = DispatchWorkItem { tunnel.stopVPNTunnel() }
        stopJob = stop
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 20, execute: stop
        )
        var connected = false
        for attempt in 0..<48 {
            let status = tunnel.status
            if status == .connected { connected = true; break }
            if status == .invalid || (status == .disconnected && attempt >= 16) { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard connected else {
            XCTFail("Disposable VPN not connected; auto-stop armed")
            return
        }
        print("APL_V6_LAB_TUN_CONNECTED_WITH_HOST20_EXTENSION25_GUARDS")

        var received = false
        var changed = false
        var matchesProxy = false
        do {
            let throughVPN = try await ipv6Witness(nil)
            received = true
            changed = throughVPN != before
            matchesProxy = throughVPN == control
            print("APL_V6_LAB_VPN_IPV6_ONLY_HTTPS_RECEIPT_CHANGED_\(changed)_MATCHES_PROXY_\(matchesProxy)")
        } catch {
            // Only the integer error code; never stringify NSError or URLs.
            print("APL_V6_LAB_VPN_IPV6_ONLY_HTTPS_FAILED_CODE_\((error as NSError).code)")
        }

        stopJob?.cancel()
        tunnel.stopVPNTunnel()
        var off = false
        for _ in 0..<40 {
            if tunnel.status == .disconnected { off = true; break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        guard off else {
            XCTFail("PacketTunnel must return OFF, extension kill timer remains armed")
            return
        }
        print("APL_V6_LAB_EXPLICIT_OFF_CONFIRMED")
        var restored = false
        for attempt in 1...3 {
            if let after = try? await ipv6Witness(nil), after == before {
                restored = true
                break
            }
            if attempt < 3 { try await Task.sleep(nanoseconds: 600_000_000) }
        }
        print("APL_V6_LAB_DIRECT_IPV6_BASELINE_RESTORED_\(restored)")
        XCTAssertTrue(received, "IPv6-only HTTPS destination must complete through PacketTunnel")
        XCTAssertTrue(changed, "Public IPv6 egress must differ from direct iPhone")
        XCTAssertTrue(matchesProxy, "PacketTunnel egress must match disposable IPv6 upstream")
        XCTAssertTrue(restored, "Direct IPv6 source must restore after VPN OFF")
#endif
    }
    /// Native IPv6 packet destination (not a VirtualDNS fake IPv4 address).
    /// SNI and the TLS certificate hostname are fixed, public and valid.
    func testBoundedPacketTunnelNativeIPv6TLSPacketViaDisposableProxy() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Requires real iPhone, signed PacketTunnel and LAN QA proxy")
#else
        guard #available(iOS 17.0, *) else { throw XCTSkip("iOS17+ QA endpoint") }
        let tunnel = try await existingOffTunnel()
        guard await nativeIPv6TLS() else {
            throw XCTSkip("Direct native IPv6 with valid TLS SNI unavailable; VPN untouched")
        }
        print("APL_V6_NATIVE_TUN_DIRECT_IPV6_SNI_TLS_PASS")
        let endpoint = NWEndpoint.hostPort(
            host: .init("192.168.1.80"), port: NWEndpoint.Port(rawValue: 18081)!)
        var lab = ProxyConfiguration(httpCONNECTProxy: endpoint)
        lab.allowFailover = false
        let fromLab: String
        let fromDirect: String
        do {
            fromDirect = try await ipv6Witness(nil)
            fromLab = try await ipv6Witness(lab)
        } catch {
            throw XCTSkip("Disposable IPv6 upstream HTTPS preflight failed; no VPN activated")
        }
        guard fromLab != fromDirect else {
            throw XCTSkip("Disposable IPv6 upstream source not independent, no VPN activated")
        }
        print("APL_V6_NATIVE_TUN_DISPOSABLE_UPSTREAM_PREFLIGHT_PASS")
        var started = false
        var timeoutJob: DispatchWorkItem?
        defer {
            timeoutJob?.cancel()
            if started { tunnel.stopVPNTunnel() }
        }
        started = true
        try tunnel.startTunnel(options: [
            "requestedByUser": NSNumber(value: true),
            "qaStopAfterSeconds": NSNumber(value: 25),
            "qaSmart3ProxyHost": "192.168.1.80" as NSString,
            "qaSmart3ProxyPort": NSNumber(value: 18081)
        ])
        let stopper = DispatchWorkItem { tunnel.stopVPNTunnel() }
        timeoutJob = stopper
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 20, execute: stopper
        )
        var connected = false
        for attempt in 0..<48 {
            let status = tunnel.status
            if status == .connected { connected = true; break }
            if status == .invalid || (status == .disconnected && attempt >= 16) { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard connected else {
            XCTFail("Native IPv6 TUN diagnostic could not reach Connected")
            return
        }
        print("APL_V6_NATIVE_TUN_PACKETTUNNEL_CONNECTED_GUARDED")

        let tunneledNativeIPv6 = await nativeIPv6TLS()
        print("APL_V6_NATIVE_TUN_LITERAL_IPV6_TLS_HTTP200_\(tunneledNativeIPv6)")
        timeoutJob?.cancel()
        tunnel.stopVPNTunnel()
        var off = false
        for _ in 0..<40 {
            if tunnel.status == .disconnected { off = true; break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        guard off else {
            XCTFail("Native IPv6 TUN QA failed to restore system VPN OFF")
            return
        }
        print("APL_V6_NATIVE_TUN_EXPLICIT_OFF_CONFIRMED")
        let directRestored = await nativeIPv6TLS()
        print("APL_V6_NATIVE_TUN_DIRECT_IPV6_SNI_TLS_RESTORED_\(directRestored)")
        XCTAssertTrue(tunneledNativeIPv6,
                      "Original IPv6 literal TCP/TLS packets must traverse the TUN and upstream")
        XCTAssertTrue(directRestored, "Direct native IPv6 TLS must work after PacketTunnel OFF")
#endif
    }

#endif
}
