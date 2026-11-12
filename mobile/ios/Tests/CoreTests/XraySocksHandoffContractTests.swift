import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class XraySocksHandoffContractTests: XCTestCase {
    func testExactLocalSocksTun2ProxyPlanWithoutDirectOrCredentials() throws {
        let p = try XraySocksHandoffPlan.prepare(
            tunFD: 17, socksPort: 39879,
            dnsBypass: ["www.gosuslugi.ru", "example.com"])
        XCTAssertEqual(p.proxyURL, "socks5://127.0.0.1:39879")
        XCTAssertEqual(p.tunnelDescriptor, 17)
        XCTAssertEqual(p.dnsBypasses, ["example.com", "www.gosuslugi.ru"])
        XCTAssertEqual(p.tun2proxyArguments,
            "tun2proxy-bin --proxy socks5://127.0.0.1:39879 --tun-fd 17" +
            " --close-fd-on-drop false --dns virtual --ipv6-enabled --verbosity warn" +
            " --dns-bypass example.com --dns-bypass www.gosuslugi.ru")
        XCTAssertFalse(p.tun2proxyArguments.contains("experimental"))
        XCTAssertFalse(p.tun2proxyArguments.contains("password"))
    }

    func testInvalidDescriptorPortOrCLIInjectionFailClosed() {
        for fd in [-1, Int.max] {
            XCTAssertThrowsError(try XraySocksHandoffPlan.prepare(
                tunFD: fd, socksPort: 39879, dnsBypass: []))
        }
        for port in [0, 80, 65536, -1] {
            XCTAssertThrowsError(try XraySocksHandoffPlan.prepare(
                tunFD: 5, socksPort: port, dnsBypass: []))
        }
        for item in ["x --experimental-scoped-direct", "evil\n--proxy=other",
                     "foo;bar", "foo'bar", "localhost", "example.com ",
                     "--help", "EXAMPLE.com", "example.com\t\0",
                     "user:pass@example.com", "127.0.0.1:443"] {
            XCTAssertThrowsError(try XraySocksHandoffPlan.prepare(
                tunFD: 5, socksPort: 39879, dnsBypass: [item]), item)
        }
    }

    func testValidIPBypassAndRejectDuplicates() throws {
        let p = try XraySocksHandoffPlan.prepare(
            tunFD: 0, socksPort: 42000,
            dnsBypass: ["203.0.113.5", "2001:db8::5"])
        XCTAssertEqual(p.dnsBypasses, ["2001:db8::5", "203.0.113.5"])
        XCTAssertThrowsError(try XraySocksHandoffPlan.prepare(
            tunFD: 0, socksPort: 42000, dnsBypass: ["example.com", "example.com"]))
        XCTAssertThrowsError(try XraySocksHandoffPlan.prepare(
            tunFD: 0, socksPort: 42000,
            dnsBypass: Array(repeating: "one.example", count: 65)))
    }

    func testStartReadyDrainAndRejectStaleCallbacks() throws {
        var gate = XrayHandoffLifecycle()
        XCTAssertEqual(gate.phase, .idle)
        let first = try gate.begin()
        XCTAssertEqual(gate.phase, .starting)
        XCTAssertThrowsError(try gate.begin())
        try gate.ready(generation: first)
        XCTAssertEqual(gate.phase, .running)
        XCTAssertThrowsError(try gate.ready(generation: first))
        XCTAssertTrue(try gate.requestStop(generation: first))
        XCTAssertFalse(try gate.requestStop(generation: first))
        try gate.drained(generation: first)
        XCTAssertEqual(gate.phase, .stopped)
        let second = try gate.begin()
        XCTAssertEqual(second, first + 1)
        XCTAssertThrowsError(try gate.ready(generation: first))
        XCTAssertThrowsError(try gate.requestStop(generation: first))
        XCTAssertEqual(gate.phase, .starting)
        XCTAssertTrue(try gate.requestStop(generation: second))
        try gate.drained(generation: second)
    }

    func testLateFailureCannotInvalidateDrainedSession() throws {
        var gate = XrayHandoffLifecycle()
        let token = try gate.begin()
        XCTAssertTrue(try gate.requestStop(generation: token))
        try gate.drained(generation: token)
        XCTAssertThrowsError(try gate.failClosed(generation: token))
        XCTAssertEqual(gate.phase, .stopped)
        let next = try gate.begin()
        XCTAssertThrowsError(try gate.failClosed(generation: token))
        XCTAssertEqual(gate.generation, next)
        XCTAssertEqual(gate.phase, .starting)
    }

    func testFailureCannotSilentlyRestart() throws {
        var gate = XrayHandoffLifecycle()
        let token = try gate.begin()
        try gate.failClosed(generation: token)
        XCTAssertEqual(gate.phase, .failedClosed)
        XCTAssertFalse(try gate.requestStop(generation: token))
        XCTAssertThrowsError(try gate.begin())
        XCTAssertThrowsError(try gate.ready(generation: token))
    }
}
