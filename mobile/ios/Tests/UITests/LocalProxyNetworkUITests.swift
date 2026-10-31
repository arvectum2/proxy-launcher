import Foundation
import Network
import XCTest

/// Real iPhone Network.framework integration tests, using an in-process
/// loopback fixture. No real proxy credentials, VPN activation or persistent
/// ProfileStore writes. Compiles the same ProxyProbe.swift as the app target.
private final class LocalProxyServer {
    enum Mode { case httpOK, http407, partialHTTP, socksOK, socksAuthRejected, silent }

    private let mode: Mode
    private let queue = DispatchQueue(label: "ru.arvectum.test.localproxy")
    private let listener: NWListener
    private var sessions: [NWConnection] = []
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(_ mode: Mode) throws {
        self.mode = mode
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start(expectation: XCTestExpectation) {
        listener.stateUpdateHandler = { state in
            if case .ready = state { expectation.fulfill() }
        }
        listener.newConnectionHandler = { [self] connection in
            sessions.append(connection)
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] data, _, _, _ in
                guard data != nil else { return }
                switch mode {
                case .httpOK:
                    connection.send(content: Data("HTTP/1.1 200 Connection established\r\n\r\n".utf8), completion: .contentProcessed { _ in })
                case .http407:
                    connection.send(content: Data("HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Digest realm=qa\r\nContent-Length: 0\r\n\r\n".utf8), completion: .contentProcessed { _ in })
                case .partialHTTP:
                    connection.send(content: Data("HTTP/1.1 200 Connection established\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
                case .socksOK:
                    self.respondSOCKS(connection, authenticated: false)
                case .socksAuthRejected:
                    self.respondSOCKS(connection, authenticated: true)
                case .silent:
                    break
                }
            }
        }
        listener.start(queue: queue)
    }

    private func respondSOCKS(_ connection: NWConnection, authenticated: Bool) {
        let greeting: Data = authenticated ? Data([5, 2]) : Data([5, 0])
        connection.send(content: greeting, completion: .contentProcessed { _ in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 512) { _, _, _, _ in
                if authenticated {
                    connection.send(content: Data([1, 1]), completion: .contentProcessed { _ in })
                } else {
                    let reply = Data([5, 0, 0, 1, 127, 0, 0, 1, 0, 80])
                    connection.send(content: reply, completion: .contentProcessed { _ in })
                }
            }
        })
    }

    func stop() {
        listener.cancel()
        sessions.forEach { $0.cancel() }
        sessions.removeAll()
    }
}

final class LocalProxyNetworkUITests: XCTestCase {
    private func profile(port: UInt16, type: ProxyType, username: String? = nil) -> ProxyProfile {
        ProxyProfile(name: "Device QA fixture", host: "127.0.0.1", port: Int(port), type: type, username: username)
    }

    private func check(mode: LocalProxyServer.Mode, type: ProxyType,
                       username: String? = nil, password: String? = nil,
                       expectedFailure: ProxyFailureReason? = nil) async throws {
        let server = try LocalProxyServer(mode)
        defer { server.stop() }
        let ready = expectation(description: "Loopback TCP listener ready")
        server.start(expectation: ready)
        await fulfillment(of: [ready], timeout: 7)
        XCTAssertNotEqual(server.port, 0)
        do {
            let result = try await ProxyProbe().resolveMeasured(profile(port: server.port, type: type, username: username), password: password)
            XCTAssertNil(expectedFailure, "Unexpectedly accepted a rejected or incomplete proxy handshake")
            XCTAssertGreaterThan(result.latencyMs, 0)
        } catch {
            guard let expectedFailure else { throw error }
            XCTAssertEqual(ProxyFailureReason.classify(error), expectedFailure)
        }
    }

    func testHTTPConnect200Handshake() async throws {
        try await check(mode: .httpOK, type: .http)
    }

    func testHTTP407DigestChallengeIsNotConsideredConnected() async throws {
        try await check(mode: .http407, type: .http, expectedFailure: .http407)
    }

    func testTruncatedHTTP200IsNotConsideredConnected() async throws {
        try await check(mode: .partialHTTP, type: .http, expectedFailure: .protocolMismatch)
    }

    func testSOCKS5NoAuthHandshake() async throws {
        try await check(mode: .socksOK, type: .socks5)
    }

    func testSOCKS5BadCredentialIsNotConnected() async throws {
        try await check(mode: .socksAuthRejected, type: .socks5, username: "fixture", password: "invalid", expectedFailure: .authentication)
    }

    func testSilentProxyStopsWithinBoundedTime() async throws {
        try await check(mode: .silent, type: .http, expectedFailure: .timeout)
    }

    func testInvalidDNSFailsClosedWithoutInventingReachability() async throws {
        let profile = ProxyProfile(name: "NXDOMAIN fixture", host: "apl-device-check.invalid", port: 12345, type: .http)
        do {
            _ = try await ProxyProbe().resolveMeasured(profile, password: nil)
            XCTFail("Reserved .invalid domain unexpectedly resolved")
        } catch {
            // On an offline device DNS queries may never answer, so a bounded
            // timeout is more truthful than asserting a received NXDOMAIN.
            let reason = ProxyFailureReason.classify(error)
            XCTAssertTrue(reason == .dns || reason == .timeout || reason == .offline,
                          "Unexpected DNS failure classification: \(reason.code)")
        }
    }

    func testTLSRejectsPlaintextProxy() async throws {
        try await check(mode: .httpOK, type: .https, expectedFailure: .tls)
    }

    func testPublicHTTPSReachabilityForWebKitTriage() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://example.com/")!)
        request.timeoutInterval = 12
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            XCTAssertEqual(status, 200, "Device network returned HTTP status \(status)")
        } catch {
            let ns = error as NSError
            throw XCTSkip("Physical iPhone network cannot reach example.com outside WebKit (NSError domain=\(ns.domain), code=\(ns.code)).")
        }
    }
}
