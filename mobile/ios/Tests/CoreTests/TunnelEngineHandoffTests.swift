import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class TunnelEngineHandoffTests: XCTestCase {
    func testStopHappensBeforeQueuedEngineDrain() async throws {
        let queue = DispatchQueue(label: "ios.engine-handoff.test.drain")
        let oldRunnerStarted = expectation(description: "old blocking runner started")
        let oldRunnerRelease = DispatchSemaphore(value: 0)
        let oldRunnerFinished = expectation(description: "old runner exited")
        queue.async {
            oldRunnerStarted.fulfill()
            _ = oldRunnerRelease.wait(timeout: .now() + 3)
            oldRunnerFinished.fulfill()
        }
        await fulfillment(of: [oldRunnerStarted], timeout: 2)
        var stopCalled = false
        try await TunnelEngineHandoff.stopAndDrain(engineQueue: queue, timeout: 1) {
            stopCalled = true
            oldRunnerRelease.signal()
        }
        XCTAssertTrue(stopCalled)
        await fulfillment(of: [oldRunnerFinished], timeout: 1)
    }

    func testBlockedOldEngineTimesOutInsteadOfStartingReplacement() async throws {
        let queue = DispatchQueue(label: "ios.engine-handoff.test.timeout")
        let oldRunnerStarted = expectation(description: "old runner started")
        let oldRunnerRelease = DispatchSemaphore(value: 0)
        queue.async {
            oldRunnerStarted.fulfill()
            _ = oldRunnerRelease.wait(timeout: .now() + 3)
        }
        await fulfillment(of: [oldRunnerStarted], timeout: 2)
        var stopCallCount = 0
        do {
            try await TunnelEngineHandoff.stopAndDrain(engineQueue: queue, timeout: 0.04) {
                stopCallCount += 1
            }
            XCTFail("Must not restart while old engine still owns its queue")
        } catch let error as TunnelEngineDrainError {
            XCTAssertEqual(error, .timeout)
        }
        XCTAssertEqual(stopCallCount, 1)
        // The queued completion arrives *after* the timeout. It must not
        // attempt a second continuation resume or crash the test process.
        oldRunnerRelease.signal()
        queue.sync {}
    }

    func testAlreadyStoppedEngineDrainsImmediately() async throws {
        let queue = DispatchQueue(label: "ios.engine-handoff.test.empty")
        var stopCallCount = 0
        try await TunnelEngineHandoff.stopAndDrain(engineQueue: queue, timeout: 1) {
            stopCallCount += 1
        }
        XCTAssertEqual(stopCallCount, 1)
    }
}
