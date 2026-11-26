import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

@MainActor private final class FakeBackendDriver: TransportBackendDriver {
    typealias Model = TransportBackendCoordinator
    enum Failure: Error { case submit, snapshot }
    var commands: [Model.Command] = []
    var running: Model.Session?
    var nativeStopped = true
    var osStopped = true
    var pendingStart = false
    var throwSnapshot = false
    var throwSubmit = false
    var throwCancel = false
    var onInspect: (() -> Void)?
    var onSubmit: ((Model.Command) -> Void)?
    var submitting = false
    var reentrant = false
    var overlaps = 0

    func allOwnedProvidersQuiescent() throws -> Bool {
        onInspect?()
        if throwSnapshot { throw Failure.snapshot }
        return nativeStopped && osStopped && !pendingStart
    }

    func submit(_ command: Model.Command) throws {
        if submitting { reentrant = true }
        submitting = true
        defer { submitting = false }
        commands.append(command)
        if case .start(let s) = command {
            if !(try allOwnedProvidersQuiescent()) { overlaps += 1 }
            running = s
            nativeStopped = false
            osStopped = false
            pendingStart = true
        }
        onSubmit?(command)
        if throwSubmit { throwSubmit = false; throw Failure.submit }
        if case .cancelTunnel = command, throwCancel { throw Failure.submit }
    }

    func connected(_ a: TransportBackendAdapter, _ s: Model.Session) {
        pendingStart = false
        a.receive(.osConnected,from:s)
        a.receive(.nativeReady,from:s)
    }

    func drain(_ a: TransportBackendAdapter, _ s: Model.Session, nativeFirst: Bool = true) {
        pendingStart = false
        if nativeFirst {
            nativeStopped = true
            a.receive(.nativeDrained,from:s)
            osStopped = true
            a.receive(.osDisconnected,from:s)
        } else {
            osStopped = true
            a.receive(.osDisconnected,from:s)
            nativeStopped = true
            a.receive(.nativeDrained,from:s)
        }
    }

    func reconcile() {
        nativeStopped = true
        osStopped = true
        pendingStart = false
        running = nil
    }
}

final class TransportBackendAdapterTests: XCTestCase {
    typealias Model = TransportBackendCoordinator

    private func plan(_ proto: TransportProtocol = .wireGuard) throws -> TransportBackendPlan {
        try .prepare(profileID:UUID(),revision:UUID(),protocol:proto,scope:.syntheticLab,
                     routes:.tunnelOnly,required: proto == .amneziaWG1 ? [.rawIPv4] : [.tcpIPv4])
    }

    @MainActor func testTwoReadyReceiptsAndBothStopOrders() async throws {
        for nativeFirst in [true,false] {
            let d=FakeBackendDriver(), a=try TransportBackendAdapter(driver:d,lease:TransportBackendLease())
            try a.begin(plan())
            let old=try XCTUnwrap(a.model.active)
            a.receive(.nativeReady,from:old)
            XCTAssertEqual(a.model.phase,.starting)
            a.receive(.nativeReady,from:old)
            XCTAssertEqual(a.model.phase,.starting)
            d.pendingStart=false
            a.receive(.osConnected,from:old)
            XCTAssertEqual(a.model.phase,.running)
            let next=try plan(.amneziaWG1)
            try a.switchTo(next)
            XCTAssertEqual(d.commands,[.start(old),.stop(old)])
            d.drain(a,old,nativeFirst:nativeFirst)
            let new=try XCTUnwrap(a.model.active)
            XCTAssertEqual(new.plan,next)
            XCTAssertEqual(d.commands,[.start(old),.stop(old),.start(new)])
            a.receive(.unexpectedExit,from:old)
            XCTAssertEqual(a.model.phase,.starting)
            d.connected(a,new)
            XCTAssertEqual(a.model.phase,.running)
            try a.stop()
            d.drain(a,new)
            XCTAssertEqual(a.model.phase,.idle)
            XCTAssertEqual(d.overlaps,0)
        }
    }

    @MainActor func testCompetingAdapterCannotAcquireLease() async throws {
        let d=FakeBackendDriver(), lease=TransportBackendLease()
        let a=try TransportBackendAdapter(driver:d,lease:lease)
        let b=try TransportBackendAdapter(driver:d,lease:lease)
        try a.begin(plan())
        let old=try XCTUnwrap(a.model.active)
        XCTAssertThrowsError(try b.begin(plan()))
        d.connected(a,old)
        try a.stop()
        XCTAssertThrowsError(try b.begin(plan()))
        d.drain(a,old)
        try b.begin(plan())
        let new=try XCTUnwrap(b.model.active)
        XCTAssertNotEqual(old.token.epoch,new.token.epoch)
        b.receive(.nativeReady,from:old)
        XCTAssertEqual(b.model.phase,.starting)
        try b.stop()
        d.drain(b,new)
        XCTAssertEqual(d.overlaps,0)
    }

    @MainActor func testStopCancelsQueuedSwitch() async throws {
        let d=FakeBackendDriver(), a=try TransportBackendAdapter(driver:d,lease:TransportBackendLease())
        try a.begin(plan())
        let old=try XCTUnwrap(a.model.active)
        d.connected(a,old)
        try a.switchTo(plan(.amneziaWG1))
        d.nativeStopped=true
        a.receive(.nativeDrained,from:old)
        try a.stop()
        d.osStopped=true
        a.receive(.osDisconnected,from:old)
        XCTAssertEqual(d.commands,[.start(old),.stop(old)])
        XCTAssertEqual(a.model.phase,.idle)
    }

    @MainActor func testSecondReceiptDoesNotOverrideLiveProviderSnapshot() async throws {
        let d=FakeBackendDriver(), a=try TransportBackendAdapter(driver:d,lease:TransportBackendLease())
        try a.begin(plan())
        let old=try XCTUnwrap(a.model.active)
        d.connected(a,old)
        try a.switchTo(plan(.amneziaWG1))
        // False/native premature receipts cannot override the live snapshot.
        a.receive(.nativeDrained,from:old)
        a.receive(.osDisconnected,from:old)
        XCTAssertEqual(d.commands,[.start(old),.stop(old),.cancelTunnel(old)])
        XCTAssertEqual(a.model.phase,.failedClosed)
        XCTAssertThrowsError(try a.reconcileFailure())
        d.reconcile()
        try a.reconcileFailure()
        try a.begin(plan())
        XCTAssertEqual(d.overlaps,0)
        let new=try XCTUnwrap(a.model.active)
        try a.stop()
        d.drain(a,new)
    }

    @MainActor func testStartupTimeoutRetainsLeaseAndRequiresReconciliation() async throws {
        let d=FakeBackendDriver(), lease=TransportBackendLease()
        let a=try TransportBackendAdapter(driver:d,lease:lease,timeout:0.03)
        let b=try TransportBackendAdapter(driver:d,lease:lease)
        try a.begin(plan())
        let old=try XCTUnwrap(a.model.active)
        a.receive(.nativeReady,from:old)
        try await waitForFailure(a)
        XCTAssertEqual(d.commands,[.start(old),.cancelTunnel(old)])
        XCTAssertThrowsError(try b.begin(plan()))
        a.receive(.osConnected,from:old)
        XCTAssertEqual(a.model.phase,.failedClosed)
        XCTAssertThrowsError(try a.reconcileFailure())
        d.reconcile()
        try a.reconcileFailure()
        try a.begin(plan())
        let new=try XCTUnwrap(a.model.active)
        XCTAssertNotEqual(old.token.epoch,new.token.epoch)
        a.receive(.failed,from:old)
        d.connected(a,new)
        try a.stop()
        d.drain(a,new)
    }

    @MainActor func testStopTimeoutDoesNotStartReplacement() async throws {
        let d=FakeBackendDriver(), a=try TransportBackendAdapter(driver:d,lease:TransportBackendLease(),timeout:0.03)
        try a.begin(plan())
        let old=try XCTUnwrap(a.model.active)
        d.connected(a,old)
        try a.switchTo(plan(.amneziaWG1))
        d.nativeStopped=true
        a.receive(.nativeDrained,from:old)
        try await waitForFailure(a)
        XCTAssertEqual(d.commands,[.start(old),.stop(old),.cancelTunnel(old)])
        a.receive(.osDisconnected,from:old)
        XCTAssertEqual(a.model.phase,.failedClosed)
        XCTAssertNil(a.model.pending)
    }

    @MainActor private func waitForFailure(_ a: TransportBackendAdapter) async throws {
        for _ in 0..<100 {
            if a.model.phase == .failedClosed { return }
            try await Task.sleep(nanoseconds:10_000_000)
        }
        XCTFail("deadline did not cancel")
    }

    @MainActor func testSynchronousDriverCallbacksAreSerialized() async throws {
        let d=FakeBackendDriver(), a=try TransportBackendAdapter(driver:d,lease:TransportBackendLease())
        d.onSubmit = { [weak a,weak d] command in
            guard let a, let d else {return}
            switch command {
            case .start(let s):d.connected(a,s)
            case .stop(let s):d.drain(a,s)
            case .cancelTunnel:break
            }
        }
        try a.begin(plan())
        XCTAssertEqual(a.model.phase,.running)
        try a.switchTo(plan(.amneziaWG1))
        XCTAssertEqual(a.model.phase,.running)
        XCTAssertEqual(a.model.active?.plan.provider,.standaloneAWG)
        try a.stop()
        XCTAssertEqual(a.model.phase,.idle)
        XCTAssertFalse(d.reentrant)
        XCTAssertEqual(d.overlaps,0)
    }

    @MainActor func testSynchronousSuccessCannotOverrideSubmitError() async throws {
        let d=FakeBackendDriver(), lease=TransportBackendLease()
        let a=try TransportBackendAdapter(driver:d,lease:lease)
        let b=try TransportBackendAdapter(driver:d,lease:lease)
        d.onSubmit = { [weak a,weak d] command in
            if case .start(let s)=command, let a, let d {d.connected(a,s)}
        }
        d.throwSubmit=true
        d.throwCancel=true
        try a.begin(plan())
        let old=try XCTUnwrap(a.model.active)
        XCTAssertEqual(a.model.phase,.failedClosed)
        XCTAssertEqual(d.commands,[.start(old),.cancelTunnel(old)])
        XCTAssertThrowsError(try b.begin(plan()))
        d.reconcile()
        d.throwSnapshot=true
        XCTAssertThrowsError(try a.reconcileFailure())
        d.throwSnapshot=false
        try a.reconcileFailure()
        d.onSubmit=nil
        d.throwCancel=false
        try b.begin(plan())
        let new=try XCTUnwrap(b.model.active)
        try b.stop()
        d.drain(b,new)
    }

    @MainActor func testContradictoryAndUnexpectedReceiptsFail() async throws {
        for receipt in [TransportBackendReceipt.nativeDrained,.osDisconnected,.unexpectedExit,.failed] {
            let d=FakeBackendDriver(), a=try TransportBackendAdapter(driver:d,lease:TransportBackendLease())
            try a.begin(plan())
            let old=try XCTUnwrap(a.model.active)
            d.connected(a,old)
            a.receive(receipt,from:old)
            XCTAssertEqual(a.model.phase,.failedClosed)
            XCTAssertEqual(d.commands,[.start(old),.cancelTunnel(old)])
            a.receive(receipt,from:old)
            XCTAssertEqual(d.commands.count,2)
        }
        let d=FakeBackendDriver(), a=try TransportBackendAdapter(driver:d,lease:TransportBackendLease())
        try a.begin(plan())
        let old=try XCTUnwrap(a.model.active)
        d.connected(a,old)
        try a.switchTo(plan(.amneziaWG1))
        d.nativeStopped=true
        a.receive(.nativeDrained,from:old)
        a.receive(.nativeReady,from:old)
        XCTAssertEqual(a.model.phase,.failedClosed)
    }

    @MainActor func testWrongSessionIdentityAndUnreconciledStartup() async throws {
        let d=FakeBackendDriver(), a=try TransportBackendAdapter(driver:d,lease:TransportBackendLease())
        d.pendingStart=true
        XCTAssertThrowsError(try a.begin(plan()))
        XCTAssertTrue(d.commands.isEmpty)
        d.reconcile()
        try a.begin(plan())
        let old=try XCTUnwrap(a.model.active)
        let impostor=Model.Session(token:old.token,plan:try plan(.amneziaWG1))
        a.receive(.nativeReady,from:impostor)
        XCTAssertEqual(a.model.phase,.failedClosed)
        XCTAssertEqual(d.commands,[.start(old),.cancelTunnel(old)])
    }

    @MainActor func testTimeoutValidation() async throws {
        let d=FakeBackendDriver()
        for value in [Double.nan,.infinity,-1,0,121] {
            XCTAssertThrowsError(try TransportBackendAdapter(driver:d,timeout:value))
        }
    }

    @MainActor func testContradictionQueuedDuringQuiescenceCheckPreventsStart() async throws {
        let d=FakeBackendDriver(), a=try TransportBackendAdapter(driver:d,lease:TransportBackendLease())
        try a.begin(plan())
        let old=try XCTUnwrap(a.model.active)
        d.connected(a,old)
        try a.switchTo(plan(.amneziaWG1))
        d.nativeStopped=true
        a.receive(.nativeDrained,from:old)
        d.osStopped=true
        d.onInspect = { [weak a] in a?.receive(.nativeReady,from:old) }
        a.receive(.osDisconnected,from:old)
        XCTAssertEqual(a.model.phase,.failedClosed)
        XCTAssertEqual(d.commands,[.start(old),.stop(old),.cancelTunnel(old)])
    }

    @MainActor func testReentrantBeginDuringSnapshotCannotStealLease() async throws {
        let d=FakeBackendDriver(), a=try TransportBackendAdapter(driver:d,lease:TransportBackendLease())
        let other=try plan(.amneziaWG1)
        d.onInspect = { [weak a] in
            guard let a else { return }
            do { try a.begin(other); XCTFail("reentrant begin succeeded") }
            catch { XCTAssertEqual(error as? TransportAdapterError,.busy) }
        }
        try a.begin(plan())
        XCTAssertEqual(d.commands.count,1)
        let s=try XCTUnwrap(a.model.active)
        XCTAssertEqual(s.plan.provider,.rustXray)
        d.onInspect=nil
        try a.stop()
        d.drain(a,s)
    }
}
