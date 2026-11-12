import Darwin
import Foundation
import Network
import NetworkExtension
import XCTest
@testable import Arvectum_Proxy_Launcher

/// Diagnostic only. Distinguishes proxy upstream reachability from the APL
/// system PacketTunnel path. Never changes VPN state or owner profiles.
final class PhysicalProxyIPFamilyReachabilityTests: XCTestCase {
    private enum ReadinessError: Error { case invalid }

    @available(iOS 17.0, *)
    private func requestFamily(
        _ source: ProxyConfiguration?, address: String, family: Int32
    ) async throws -> Bool {
        let config = URLSessionConfiguration.ephemeral
        if let source { config.proxyConfigurations = [source] }
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let client = URLSession(configuration: config)
        defer { client.invalidateAndCancel() }
        guard let url = URL(string: address) else { throw ReadinessError.invalid }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await client.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 128,
              let raw = String(data: data, encoding: .utf8) else {
            throw ReadinessError.invalid
        }
        let ip = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var storage = in6_addr()
        return ip.withCString { inet_pton(family, $0, &storage) == 1 }
    }

    @available(iOS 17.0, *)
    private func proxyConfig(_ resolved: ProxyProfile, username: String, password: String) throws -> ProxyConfiguration {
        guard let port = NWEndpoint.Port(rawValue: UInt16(resolved.port)) else {
            throw ReadinessError.invalid
        }
        let endpoint = NWEndpoint.hostPort(host: .init(resolved.host), port: port)
        var proxy: ProxyConfiguration
        switch resolved.type {
        case .http: proxy = ProxyConfiguration(httpCONNECTProxy: endpoint)
        case .https:
            proxy = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: .init())
        case .socks5: proxy = ProxyConfiguration(socksv5Proxy: endpoint)
        case .auto: throw ReadinessError.invalid
        }
        proxy.applyCredential(username: username, password: password)
        proxy.allowFailover = false // Never silently go direct.
        return proxy
    }

    func testExistingProxiesReachIPv4AndIPv6OnlyHTTPSWithoutEnablingVPN() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Needs existing owner proxies on physical iPhone")
#else
        guard #available(iOS 17.0, *) else { throw XCTSkip("ProxyConfiguration requires iOS 17+") }
        // An app-level proxy diagnosis cannot be interpreted while another
        // APL system VPN route is active; the manager is never saved or changed.
        let managers: [NETunnelProviderManager] = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { list, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: list ?? []) }
            }
        }
        for manager in managers {
            guard (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == "ru.arvectum.proxylauncher.ios.PacketTunnel" else { continue }
            guard manager.connection.status == .disconnected ||
                  manager.connection.status == .invalid else {
                throw XCTSkip("Existing APL VPN is not OFF; per-session diagnosis aborted")
            }
        }
        let store = try ProfileStore()
        let profiles = store.listProfiles()
        XCTAssertEqual(profiles.count, 3, "Three existing profiles expected")
        let probe = ProxyProbe()
        var ipv4Success = 0
        var ipv6Success = 0
        for (idx, profile) in profiles.enumerated() {
            guard let user = profile.username, !user.isEmpty,
                  let pass = try store.password(for: profile.id), !pass.isEmpty else {
                XCTFail("Existing proxy index \(idx + 1) lost Keychain credentials")
                continue
            }
            do {
                let resolved = try await probe.resolveMeasured(profile, password: pass).profile
                let config = try proxyConfig(resolved, username: user, password: pass)
                let ipv4OK: Bool
                let ipv6OK: Bool
                do {
                    ipv4OK = try await requestFamily(config, address: "https://ipv4.icanhazip.com", family: AF_INET)
                } catch {
                    ipv4OK = false
                }
                do {
                    ipv6OK = try await requestFamily(config, address: "https://api6.ipify.org", family: AF_INET6)
                } catch {
                    ipv6OK = false
                }
                if ipv4OK { ipv4Success += 1 }
                if ipv6OK { ipv6Success += 1 }
                print("APL_PROXY_FAMILY_QA_INDEX_\(idx + 1)_IPV4_\(ipv4OK)_IPV6_\(ipv6OK)")
            } catch {
                print("APL_PROXY_FAMILY_QA_INDEX_\(idx + 1)_PROXY_HANDSHAKE_FAILED")
            }
        }
        print("APL_PROXY_FAMILY_QA_IPV4_\(ipv4Success)_OF_\(profiles.count)_IPV6_\(ipv6Success)_OF_\(profiles.count)")
        // This is a DIAGNOSTIC, not an availability contract: proxy operators
        // may block the echo hosts. Report the counts, not a false product failure.
#endif
    }

    /// IPv6-only endpoints other than api6.ipify.org. First prove each public
    /// endpoint reachable directly, then check upstream reachability through
    /// each existing authenticated proxy, without activating system VPN.
    func testAlternateIPv6OnlyEndpointsAcrossExistingProxiesReadOnly() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Physical owner iPhone Keychain and network required")
#else
        guard #available(iOS 17.0, *) else { throw XCTSkip("ProxyConfiguration iOS17+") }
        let managers: [NETunnelProviderManager] = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { list, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: list ?? []) }
            }
        }
        for manager in managers {
            guard (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == "ru.arvectum.proxylauncher.ios.PacketTunnel" else { continue }
            guard manager.connection.status == .disconnected ||
                  manager.connection.status == .invalid else {
                throw XCTSkip("Owner APL VPN not OFF; abort read-only upstream QA")
            }
        }
        let endpoints = ["https://v6.ident.me", "https://ipv6.icanhazip.com"]
        var directAvailable = [Bool]()
        for endpoint in endpoints {
            let valid = (try? await requestFamily(nil, address: endpoint, family: AF_INET6)) == true
            directAvailable.append(valid)
        }
        print("APL_IPV6_ALTERNATES_DIRECT_ENDPOINT1_\(directAvailable[0])_ENDPOINT2_\(directAvailable[1])")
        guard directAvailable.contains(true) else {
            throw XCTSkip("Neither alternate public IPv6-only endpoint works directly on owner iPhone")
        }
        let store = try ProfileStore()
        let profiles = store.listProfiles()
        XCTAssertEqual(profiles.count, 3, "Three original stored profiles expected")
        let probe = ProxyProbe()
        var success = [0, 0]
        for (index, profile) in profiles.enumerated() {
            guard let user = profile.username, !user.isEmpty,
                  let pass = try store.password(for: profile.id), !pass.isEmpty else {
                XCTFail("Saved Keychain credentials missing at anonymous profile index \(index + 1)")
                continue
            }
            var results = [false, false]
            do {
                let resolved = try await probe.resolveMeasured(profile, password: pass).profile
                let config = try proxyConfig(resolved, username: user, password: pass)
                for target in endpoints.indices where directAvailable[target] {
                    results[target] = (try? await requestFamily(
                        config, address: endpoints[target], family: AF_INET6
                    )) == true
                    if results[target] { success[target] += 1 }
                }
            } catch {
                // Never print error: it may include the remote proxy endpoint.
            }
            print("APL_IPV6_ALTERNATES_PROXY_INDEX_\(index + 1)_ENDPOINT1_\(results[0])_ENDPOINT2_\(results[1])")
        }
        print("APL_IPV6_ALTERNATES_UPSTREAM_ENDPOINT1_\(success[0])_OF_\(profiles.count)")
        print("APL_IPV6_ALTERNATES_UPSTREAM_ENDPOINT2_\(success[1])_OF_\(profiles.count)")
        // This intentionally does not assert provider success: the purpose is
        // to classify external upstream reachability, not claim app breakage.
#endif
    }

}
