import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class Smart4OriginalFlowTraceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testOriginalNativeFlowRequiresOneIdFamilyAndBothPayloadDirections() {
        var trace = Smart4OriginalFlowTrace()
        for (i, code) in [1, 10, 7, 8, 9].enumerated() {
            trace.record(host: "www.apple.com", connectionID: 101,
                         event: Int32(code), at: start.addingTimeInterval(Double(i)))
        }
        let summary = trace.summary(at: start.addingTimeInterval(6))
        XCTAssertEqual(summary.originalDirectPayload, 1)
        XCTAssertEqual(summary.observedFlows, 1)
        XCTAssertEqual(summary.conflicted, 0)
        XCTAssertFalse(summary.externalEgressVerified)
    }

    func testCrossConnectionEventsNeverBecomeOneNativeFlow() {
        var trace = Smart4OriginalFlowTrace()
        for (id, event) in [(UInt64(1), Int32(7)), (2, 8), (3, 9), (4, 10)] {
            trace.record(host: "www.apple.com", connectionID: id, event: event, at: start)
        }
        XCTAssertEqual(trace.summary(at: start).originalDirectPayload, 0)
    }

    func testSameIdWithDifferentExactHostsFailsClosed() {
        var trace = Smart4OriginalFlowTrace()
        for code: Int32 in [1, 10, 7, 8, 9] {
            trace.record(host: code == 9 ? "www.apple.com.cn" : "www.apple.com",
                         connectionID: 9, event: code, at: start)
        }
        XCTAssertEqual(trace.summary(at: start).originalDirectPayload, 0)
        XCTAssertEqual(trace.summary(at: start).conflicted, 1)
    }

    func testOnlyExactFixedLabHostCanBeRecorded() {
        var trace = Smart4OriginalFlowTrace()
        for host in ["example.com", "192.168.1.80", "WWW.APPLE.COM", "www.apple.com.", ""] {
            trace.record(host: host, connectionID: 11, event: 0, at: start)
        }
        trace.record(host: "www.apple.com", connectionID: 0, event: 0, at: start)
        trace.record(host: "www.apple.com", connectionID: 7, event: 12, at: start)
        XCTAssertEqual(trace.summary(at: start).observedFlows, 0)
    }

    func testProxyHandshakeIsNotExternalEgressProof() {
        var trace = Smart4OriginalFlowTrace()
        trace.record(host: "www.apple.com.cn", connectionID: 11, event: 0, at: start)
        let result = trace.summary(at: start)
        XCTAssertEqual(result.proxyHandshakeAccepted, 1)
        XCTAssertEqual(result.originalDirectPayload, 0)
        XCTAssertFalse(result.externalEgressVerified)
    }

    func testDirectSocketWithoutNativeSameFlowRecoveryIsInconclusive() {
        var trace = Smart4OriginalFlowTrace()
        for code: Int32 in [10, 6, 8, 9] {
            trace.record(host: "www.apple.com", connectionID: 7, event: code, at: start)
        }
        XCTAssertEqual(trace.summary(at: start).originalDirectPayload, 0)
    }

    func testTwoPhysicalAddressFamiliesConflict() {
        var trace = Smart4OriginalFlowTrace()
        for code: Int32 in [1, 10, 11, 7, 8, 9] {
            trace.record(host: "www.apple.com", connectionID: 88, event: code, at: start)
        }
        XCTAssertEqual(trace.summary(at: start).conflicted, 1)
        XCTAssertEqual(trace.summary(at: start).originalDirectPayload, 0)
    }

    func testDuplicateRecoveryOrPayloadFailsClosed() {
        for duplicated: Int32 in [7, 8, 9] {
            var trace = Smart4OriginalFlowTrace()
            for code: Int32 in [1, 10, 7, 8, 9, duplicated] {
                trace.record(host: "www.apple.com", connectionID: 12, event: code, at: start)
            }
            XCTAssertEqual(trace.summary(at: start).conflicted, 1)
            XCTAssertEqual(trace.summary(at: start).originalDirectPayload, 0)
        }
    }

    func testMissingReplyFailsClosed() {
        var trace = Smart4OriginalFlowTrace()
        for code: Int32 in [1, 10, 7, 8] {
            trace.record(host: "www.apple.com", connectionID: 10, event: code, at: start)
        }
        XCTAssertEqual(trace.summary(at: start).originalDirectPayload, 0)
        XCTAssertEqual(trace.summary(at: start).inconclusive, 1)
    }

    func testTTLExpiresAndResetClearsEvidence() {
        var trace = Smart4OriginalFlowTrace()
        trace.record(host: "www.apple.com", connectionID: 1, event: 0, at: start)
        XCTAssertEqual(trace.summary(at: start.addingTimeInterval(61)).observedFlows, 0)
        trace.record(host: "www.apple.com", connectionID: 2, event: 0,
                     at: start.addingTimeInterval(62))
        XCTAssertEqual(trace.summary(at: start.addingTimeInterval(62)).observedFlows, 1)
        trace.reset()
        XCTAssertEqual(trace.summary(at: start.addingTimeInterval(62)).observedFlows, 0)
    }

    func testCapacityDoesNotEvictEarlierEvidenceAsProof() {
        var trace = Smart4OriginalFlowTrace()
        for id in 1...(Smart4OriginalFlowTrace.maxFlows + 1) {
            trace.record(host: "www.apple.com", connectionID: UInt64(id), event: 0, at: start)
        }
        let result = trace.summary(at: start)
        XCTAssertTrue(result.overflowed)
        XCTAssertEqual(result.observedFlows, Smart4OriginalFlowTrace.maxFlows)
        XCTAssertFalse(result.externalEgressVerified)
    }

    func testBackwardClockEvidenceNeverCertifiesOriginalFlow() {
        var trace = Smart4OriginalFlowTrace()
        trace.record(host: "www.apple.com", connectionID: 99, event: 1,
                     at: start.addingTimeInterval(2))
        trace.record(host: "www.apple.com", connectionID: 99, event: 10, at: start)
        for code: Int32 in [7, 8, 9] {
            trace.record(host: "www.apple.com", connectionID: 99, event: code,
                         at: start.addingTimeInterval(3))
        }
        XCTAssertEqual(trace.summary(at: start.addingTimeInterval(4)).conflicted, 1)
        XCTAssertEqual(trace.summary(at: start.addingTimeInterval(4)).originalDirectPayload, 0)
    }
}
