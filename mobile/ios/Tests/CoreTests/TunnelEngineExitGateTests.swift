import Dispatch
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class TunnelEngineExitGateTests: XCTestCase {
    func testUnplannedZeroCodeExitFailsClosed() {
        let gate = TunnelEngineExitGate()
        let token = gate.begin()
        XCTAssertTrue(gate.isRunning(token))
        XCTAssertTrue(gate.markUnexpectedExit(token))
        XCTAssertFalse(gate.isRunning(token))
        XCTAssertTrue(gate.shouldCancelTunnel(token))
        XCTAssertFalse(gate.markUnexpectedExit(token))
    }

    func testIntentionalStopInvalidatesLateRunnerExit() {
        let gate = TunnelEngineExitGate()
        let old = gate.begin()
        gate.invalidate()
        XCTAssertFalse(gate.markUnexpectedExit(old))
        XCTAssertFalse(gate.shouldCancelTunnel(old))
    }

    func testFailoverCannotBeCancelledByStaleCallback() {
        let gate = TunnelEngineExitGate()
        let first = gate.begin()
        XCTAssertTrue(gate.markUnexpectedExit(first))
        gate.invalidate()
        let next = gate.begin()
        XCTAssertNotEqual(first, next)
        XCTAssertFalse(gate.shouldCancelTunnel(first))
        XCTAssertFalse(gate.markUnexpectedExit(first))
        XCTAssertTrue(gate.isRunning(next))
        XCTAssertTrue(gate.markUnexpectedExit(next))
        XCTAssertTrue(gate.shouldCancelTunnel(next))
    }

    func testConcurrentReturnClaimsFailureOnlyOnce() {
        let gate = TunnelEngineExitGate()
        let token = gate.begin()
        let lock = NSLock()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "ios.engine-exit.claim", attributes: .concurrent)
        var claims = 0
        for _ in 0..<64 {
            group.enter()
            queue.async {
                if gate.markUnexpectedExit(token) {
                    lock.lock()
                    claims += 1
                    lock.unlock()
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)
        XCTAssertEqual(claims, 1)
    }

    func testInvalidationSuppressesPendingCancellation() {
        let gate = TunnelEngineExitGate()
        let token = gate.begin()
        XCTAssertTrue(gate.markUnexpectedExit(token))
        gate.invalidate()
        XCTAssertFalse(gate.shouldCancelTunnel(token))
    }
}
