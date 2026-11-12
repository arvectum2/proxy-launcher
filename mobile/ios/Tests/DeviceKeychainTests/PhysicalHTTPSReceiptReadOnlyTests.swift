import Foundation
import Network
import XCTest
@testable import Arvectum_Proxy_Launcher

/// Physical-device-only signed QA. Verifies that a real HTTPS echo response
/// returns through authenticated proxies, independently of the system VPN.
/// Never prints credentials, proxy endpoints, profile UUIDs, or public IPs.
final class PhysicalHTTPSReceiptReadOnlyTests: XCTestCase {
    private enum ReceiptError: Error {
        case invalidReceipt
        case missingCredentials
        case unresolvedProxy
    }

    @available(iOS 17.0, *)
    private func echoOrigin(nonce: String, via proxy: ProxyConfiguration?) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 18
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let proxy { config.proxyConfigurations = [proxy] }

        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        guard let url = URL(string: "https://httpbingo.org/get?qa_nonce=\(nonce)") else {
            throw ReceiptError.invalidReceipt
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (body, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let args = object["args"] as? [String: Any],
              let origin = object["origin"] as? String,
              !origin.isEmpty else {
            throw ReceiptError.invalidReceipt
        }
        let echoed = (args["qa_nonce"] as? [String])?.first
            ?? (args["qa_nonce"] as? String)
        guard echoed == nonce else { throw ReceiptError.invalidReceipt }
        return origin // Never emit this string to XCTest logs or attachments.
    }

    func testExistingProfilesProduceExternalHTTPSNonceWithoutSystemVPN() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires existing profiles and Keychain on physical owner iPhone")
        #else
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("Apple per-session ProxyConfiguration requires iOS 17+")
        }
        let store = try ProfileStore()
        let profiles = store.listProfiles()
        XCTAssertEqual(profiles.count, 3, "Expected 3 unchanged existing profiles")

        let baselineNonce = UUID().uuidString
        let directOrigin = try await echoOrigin(nonce: baselineNonce, via: nil)
        let probe = ProxyProbe()
        var verified = 0

        for (index, profile) in profiles.enumerated() {
            guard let user = profile.username, !user.isEmpty,
                  let password = try store.password(for: profile.id), !password.isEmpty else {
                XCTFail("Proxy index \(index + 1) authentication metadata is unavailable")
                continue
            }
            do {
                let resolved = try await probe.resolveMeasured(profile, password: password).profile
                guard let port = NWEndpoint.Port(rawValue: UInt16(resolved.port)) else {
                    throw ReceiptError.unresolvedProxy
                }
                let endpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host(resolved.host), port: port
                )
                var proxy: ProxyConfiguration
                switch resolved.type {
                case .http: proxy = ProxyConfiguration(httpCONNECTProxy: endpoint)
                case .https:
                    proxy = ProxyConfiguration(
                        httpCONNECTProxy: endpoint,
                        tlsOptions: NWProtocolTLS.Options()
                    )
                case .socks5: proxy = ProxyConfiguration(socksv5Proxy: endpoint)
                case .auto: throw ReceiptError.unresolvedProxy
                }
                proxy.allowFailover = false
                proxy.applyCredential(username: user, password: password)

                let origin = try await echoOrigin(nonce: UUID().uuidString, via: proxy)
                if origin != directOrigin {
                    verified += 1
                    print("APL_HTTPS_QA_INDEX_\(index + 1)_NONCE_AND_EGRESS_DISTINCT_PASS")
                } else {
                    print("APL_HTTPS_QA_INDEX_\(index + 1)_EGRESS_NOT_DISTINCT")
                }
            } catch {
                // No raw error logging: Network.framework errors can embed
                // the user's proxy host or other private connection details.
                print("APL_HTTPS_QA_INDEX_\(index + 1)_RECEIPT_FAILED")
            }
        }
        print("APL_HTTPS_QA_VERIFIED_\(verified)_OF_\(profiles.count)")
        XCTAssertGreaterThan(verified, 0,
            "No proxy showed a nonce-confirmed HTTPS response with distinct egress")
        #endif
    }
}
