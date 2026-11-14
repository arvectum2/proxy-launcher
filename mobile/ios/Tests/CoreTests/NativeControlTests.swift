import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

@MainActor private final class NativeEndpointFixture: NativeControlEndpoint {
    let provider: TransportProvider
    var status: NativeControlOSStatus = .off
    var state: TransportNativeResponse.State = .ready
    var drainState: TransportNativeResponse.State = .drained
    var wrongReceipt = false
    var stopFinishes = true
    var starts = 0, stops = 0
    var actions: [TransportNativeRequest.Action] = []
    init(_ provider: TransportProvider) { self.provider = provider }
    func start(_ session: TransportBackendCoordinator.Session, identity: TransportNativeIdentity) throws {
        starts += 1; status = .connected
    }
    func exchange(_ request: TransportNativeRequest) async throws -> TransportNativeResponse {
        actions.append(request.action)
        let source = wrongReceipt ? TransportNativeRequest(identity: request.identity, action: request.action) : request
        return .init(request: source, state: request.action == .drain ? drainState : state)
    }
    func stop() throws { stops += 1; status = stopFinishes ? .off : .stopping }
}

final class NativeControlTests: XCTestCase {
    private func plan(_ proto: TransportProtocol) throws -> TransportBackendPlan {
        try .prepare(profileID: UUID(), revision: UUID(), protocol: proto, scope: .syntheticLab, routes: .tunnelOnly, required: [.tcpIPv4])
    }
    @MainActor private func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for lifecycle")
    }
    @MainActor private func system(_ x: NativeEndpointFixture, _ w: NativeEndpointFixture, verified: Bool = true) throws -> (TransportBackendAdapter, OwnedNativeControlSlot, OwnedNativeControlSlot) {
        let xs = OwnedNativeControlSlot(endpoint: x, initialNativeQuiescenceVerified: verified), ws = OwnedNativeControlSlot(endpoint: w, initialNativeQuiescenceVerified: true)
        let d = try OwnedTransportDispatcher(xray: xs, awg: ws)
        let a = try TransportBackendAdapter(driver: d, lease: TransportBackendLease(), timeout: 2)
        xs.onReceipt = { [weak d, weak xs] e,s in if let xs { d?.receive(e,from:xs,session:s) } }
        ws.onReceipt = { [weak d, weak ws] e,s in if let ws { d?.receive(e,from:ws,session:s) } }
        d.onReceipt = { [weak a] in a?.receive($0,from:$1) }
        return (a,xs,ws)
    }
    func testBoundIdentityAndFreshRequest() throws {
        let id = TransportNativeIdentity(epoch: UUID(), generation: 1, provider: "standalone-awg")
        let other = TransportNativeIdentity(epoch: UUID(), generation: 1, provider: "standalone-awg")
        var c = TransportNativeControlState()
        XCTAssertThrowsError(try c.bind(id,provider:"rust-xray"))
        try c.bind(id,provider:"standalone-awg")
        XCTAssertThrowsError(try c.bind(other,provider:"standalone-awg"))
        let req = TransportNativeRequest(identity:id,action:.observe)
        XCTAssertEqual(try c.response(to:req).state,.starting)
        try c.ready()
        let reply = try c.response(to:req)
        XCTAssertEqual(reply.state,.ready)
        XCTAssertTrue(reply.matches(req))
        XCTAssertFalse(reply.matches(.init(identity:id,action:.observe)))
        XCTAssertThrowsError(try c.response(to:.init(identity:other,action:.observe)))
        XCTAssertThrowsError(try c.finishDrain())
        try c.beginDrain(); XCTAssertEqual(try c.response(to:req).state,.draining)
        try c.finishDrain(); XCTAssertEqual(try c.response(to:req).state,.drained)
        XCTAssertThrowsError(try c.ready())
        XCTAssertEqual(try TransportNativeCodec.decode(TransportNativeResponse.self,TransportNativeCodec.encode(reply)),reply)
        XCTAssertThrowsError(try TransportNativeCodec.decode(TransportNativeResponse.self,Data(repeating:0,count:1025)))
        c.fail(); XCTAssertEqual(try c.response(to:req).state,.failed)
    }
    @MainActor func testSwitchWaitsForNativeDrainAndOSOff() async throws {
        let x = NativeEndpointFixture(.rustXray), w = NativeEndpointFixture(.standaloneAWG)
        let (a,xs,ws) = try system(x,w)
        try a.begin(plan(.wireGuard)); try await waitFor { a.model.phase == .running }
        x.stopFinishes = false
        try a.switchTo(plan(.amneziaWG1)); try await waitFor { x.stops == 1 }
        XCTAssertEqual(a.model.phase,.stopping); XCTAssertEqual(w.starts,0); XCTAssertFalse(try xs.isQuiescent())
        x.status = .off
        try await waitFor { a.model.phase == .running && w.starts == 1 }
        XCTAssertTrue(try xs.isQuiescent()); XCTAssertFalse(try ws.isQuiescent())
        try a.stop(); try await waitFor { a.model.phase == .idle }
        XCTAssertTrue(try ws.isQuiescent())
    }
    @MainActor func testOSConnectedWithoutMatchingNativeReplyCancels() async throws {
        let x = NativeEndpointFixture(.rustXray), w = NativeEndpointFixture(.standaloneAWG)
        let (a,xs,_) = try system(x,w)
        x.wrongReceipt = true
        try a.begin(plan(.wireGuard)); try await waitFor { a.model.phase == .failedClosed }
        XCTAssertEqual(x.stops,1); XCTAssertFalse(try xs.isQuiescent()); XCTAssertThrowsError(try a.reconcileFailure())
        XCTAssertEqual(w.starts,0)
    }
    @MainActor func testMissingDrainCannotSwitchOrClaimOff() async throws {
        let x = NativeEndpointFixture(.rustXray), w = NativeEndpointFixture(.standaloneAWG)
        let (a,xs,_) = try system(x,w)
        try a.begin(plan(.wireGuard)); try await waitFor { a.model.phase == .running }
        x.drainState = .draining
        try a.switchTo(plan(.amneziaWG1)); try await waitFor { a.model.phase == .failedClosed }
        XCTAssertEqual(x.stops,1); XCTAssertEqual(w.starts,0); XCTAssertFalse(try xs.isQuiescent())
    }
    @MainActor func testInitialOSOffWithoutNativeProofRejectsStart() async throws {
        let x = NativeEndpointFixture(.rustXray), w = NativeEndpointFixture(.standaloneAWG)
        let (a,_,_) = try system(x,w,verified:false)
        XCTAssertThrowsError(try a.begin(plan(.wireGuard))); XCTAssertEqual(x.starts,0)
    }
}
