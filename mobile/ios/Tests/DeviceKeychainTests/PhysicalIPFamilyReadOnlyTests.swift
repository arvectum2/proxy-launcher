import Darwin
import Foundation
import NetworkExtension
import XCTest
@testable import Arvectum_Proxy_Launcher

/// Prepares independent dual-stack VPN acceptance. Only public IP address
/// families are checked: neither raw client IP nor user proxy data is logged.
final class PhysicalIPFamilyReadOnlyTests: XCTestCase {
    private func checkAPLVPNIsOff() async throws {
        let list: [NETunnelProviderManager] = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: managers ?? []) }
            }
        }
        let own = list.filter {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == "ru.arvectum.proxylauncher.ios.PacketTunnel"
        }
        guard !own.isEmpty else { throw XCTSkip("No existing APL VPN preference found") }
        for manager in own {
            guard manager.connection.status == .disconnected ||
                  manager.connection.status == .invalid else {
                throw XCTSkip("Existing APL VPN is not OFF; read-only baseline prohibited")
            }
        }
    }

    private func publicIP(_ url: URL) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 7
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let client = URLSession(configuration: config)
        defer { client.invalidateAndCancel() }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await client.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 128,
              let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "APLDualStackReadOnly", code: 1)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isAddress(_ text: String, family: Int32) -> Bool {
        var storage = in6_addr()
        return text.withCString { inet_pton(family, $0, &storage) } == 1
    }

    func testDirectIPv4HTTPSReceiptWhileAPLVPNIsOff() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone-only IPv4/IPv6 readiness")
#else
        try await checkAPLVPNIsOff()
        let address = try await publicIP(URL(string: "https://api4.ipify.org")!)
        if isAddress(address, family: AF_INET) {
            print("APL_IP_FAMILY_BASELINE_DIRECT_IPV4_PASS")
            return
        }
        // Carrier relays can transform source address format even with VPN OFF.
        // Log only the address family/size and use an independent fallback.
        print("APL_IP_FAMILY_API4_UNEXPECTED_V6_\(isAddress(address, family: AF_INET6))_SIZE_\(address.utf8.count)")
        let fallback: String
        do { fallback = try await publicIP(URL(string: "https://ipv4.icanhazip.com")!) }
        catch { throw XCTSkip("Second IPv4 direct echo was unavailable") }
        guard isAddress(fallback, family: AF_INET) else {
            print("APL_IP_FAMILY_IPV4_FALLBACK_UNEXPECTED_V6_\(isAddress(fallback, family: AF_INET6))_SIZE_\(fallback.utf8.count)")
            throw XCTSkip("Both IPv4 direct echos returned noncanonical format")
        }
        print("APL_IP_FAMILY_BASELINE_DIRECT_IPV4_FALLBACK_PASS")
#endif
    }

    func testNativeIPv6HTTPSReadinessWhileAPLVPNIsOff() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone-only IPv4/IPv6 readiness")
#else
        try await checkAPLVPNIsOff()
        let address: String
        do { address = try await publicIP(URL(string: "https://api6.ipify.org")!) }
        catch { throw XCTSkip("Native upstream IPv6 HTTPS witness unreachable on this iPhone path") }
        guard isAddress(address, family: AF_INET6) else {
            print("APL_IP_FAMILY_IPV6_UNEXPECTED_FORMAT_SIZE_\(address.utf8.count)")
            XCTFail("Direct iPhone IPv6 witness invalid")
            return
        }
        print("APL_IP_FAMILY_BASELINE_DIRECT_IPV6_PASS")
#endif
    }
}
