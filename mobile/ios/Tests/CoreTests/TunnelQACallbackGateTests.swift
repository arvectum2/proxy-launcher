import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class TunnelQACallbackGateTests: XCTestCase {
    func testOnlyCurrentSessionMayAct() {
        let gate = TunnelQACallbackGate()
        var count = 0
        XCTAssertFalse(gate.performIfCurrent(0) { count += 1 })
        let token = gate.begin()
        XCTAssertTrue(gate.performIfCurrent(token) { count += 1 })
        XCTAssertEqual(count, 1)
        XCTAssertTrue(gate.isCurrent(token))
    }

    func testExplicitStopSuppressesOldTimeoutAndReset() {
        let gate = TunnelQACallbackGate()
        let old = gate.begin()
        gate.invalidate()
        var sideEffects = 0
        XCTAssertFalse(gate.performIfCurrent(old) { sideEffects += 1 })
        XCTAssertFalse(gate.isCurrent(old))
        XCTAssertEqual(sideEffects, 0)
    }

    func testReconnectCannotBeStoppedByPreviousSessionTimer() {
        let gate = TunnelQACallbackGate()
        let first = gate.begin()
        gate.invalidate()
        let second = gate.begin()
        XCTAssertNotEqual(first, second)
        var cancelledNew = false
        XCTAssertFalse(gate.performIfCurrent(first) { cancelledNew = true })
        XCTAssertTrue(gate.performIfCurrent(second) { })
        XCTAssertFalse(cancelledNew)
    }

    func testRepeatedStartWithoutStopStillInvalidatesOldGeneration() {
        let gate = TunnelQACallbackGate()
        let first = gate.begin()
        let second = gate.begin()
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(gate.performIfCurrent(first) { XCTFail("stale callback") })
        XCTAssertTrue(gate.isCurrent(second))
    }

    func testSynchronousStopInsideCallbackIsSafe() {
        let gate = TunnelQACallbackGate()
        let token = gate.begin()
        XCTAssertTrue(gate.performIfCurrent(token) { gate.invalidate() })
        XCTAssertFalse(gate.isCurrent(token))
        XCTAssertFalse(gate.performIfCurrent(token) { XCTFail("already stopped") })
    }

    func testConcurrentStaleCallbacksStayBlockedAfterReconnect() {
        let gate = TunnelQACallbackGate()
        let first = gate.begin()
        gate.invalidate()
        let second = gate.begin()
        let lock = NSLock()
        var staleExecutions = 0
        DispatchQueue.concurrentPerform(iterations: 128) { _ in
            gate.performIfCurrent(first) {
                lock.lock()
                staleExecutions += 1
                lock.unlock()
            }
        }
        XCTAssertEqual(staleExecutions, 0)
        XCTAssertTrue(gate.performIfCurrent(second) { })
    }
}
