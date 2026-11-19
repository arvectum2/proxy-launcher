import XCTest
@testable import ArvectumProxyLauncherIOSCore

@MainActor private final class OwnedSlotFixture: OwnedTransportSlot {
    typealias Model = TransportBackendCoordinator
    let provider: TransportProvider
    var idle = true
    var snapshots = 0
    var snapshotError = false
    enum Failure: Error { case observation }
    var commands: [Model.Command] = []
    var onSubmit: ((Model.Command) -> Void)?
    init(_ provider: TransportProvider) { self.provider = provider }
    func isQuiescent() throws -> Bool {
        snapshots += 1
        if snapshotError { throw Failure.observation }
        return idle
    }
    func submit(_ command: Model.Command) throws {
        commands.append(command)
        if case .start = command { idle = false }
        onSubmit?(command)
    }
}

final class OwnedTransportDispatcherTests: XCTestCase {
    private func plan(_ proto: TransportProtocol) throws -> TransportBackendPlan {
        try .prepare(profileID: UUID(), revision: UUID(), protocol: proto,
                     scope: .syntheticLab, routes: .tunnelOnly,
                     required: proto == .amneziaWG1 ? [.rawIPv4] : [.tcpIPv4])
    }

    @MainActor func testCrossProviderSwitchRequiresBothSlotsOffAndDropsStaleReceipts() async throws {
        let x = OwnedSlotFixture(.rustXray), w = OwnedSlotFixture(.standaloneAWG)
        let d = try OwnedTransportDispatcher(xray: x, awg: w)
        let a = try TransportBackendAdapter(driver: d, lease: TransportBackendLease())
        d.onReceipt = { [weak a] in a?.receive($0, from: $1) }
        try a.begin(plan(.wireGuard))
        let old = try XCTUnwrap(a.model.active)
        d.receive(.nativeReady, from: x, session: old)
        d.receive(.osConnected, from: x, session: old)
        try a.switchTo(plan(.amneziaWG1))
        XCTAssertTrue(w.commands.isEmpty)
        x.idle = true
        d.receive(.nativeDrained, from: x, session: old)
        XCTAssertTrue(w.commands.isEmpty)
        d.receive(.osDisconnected, from: x, session: old)
        let next = try XCTUnwrap(a.model.active)
        XCTAssertEqual(w.commands, [.start(next)])
        XCTAssertEqual(x.commands, [.start(old), .stop(old)])
        d.receive(.failed, from: x, session: old)
        XCTAssertEqual(a.model.phase, .starting)
        d.receive(.nativeReady, from: w, session: next)
        d.receive(.osConnected, from: w, session: next)
        XCTAssertEqual(a.model.phase, .running)
        try a.stop(); w.idle = true
        d.receive(.nativeDrained, from: w, session: next)
        d.receive(.osDisconnected, from: w, session: next)
        XCTAssertEqual(a.model.phase, .idle)
    }

    @MainActor func testWrongSlotReceiptFailsClosedAndNeverDispatchesToWrongSlot() async throws {
        let x = OwnedSlotFixture(.rustXray), w = OwnedSlotFixture(.standaloneAWG)
        let d = try OwnedTransportDispatcher(xray: x, awg: w)
        let a = try TransportBackendAdapter(driver: d, lease: TransportBackendLease())
        d.onReceipt = { [weak a] in a?.receive($0, from: $1) }
        try a.begin(plan(.vlessReality))
        let current = try XCTUnwrap(a.model.active)
        d.receive(.nativeReady, from: w, session: current)
        XCTAssertEqual(a.model.phase, .failedClosed)
        XCTAssertEqual(x.commands, [.start(current), .cancelTunnel(current)])
        XCTAssertTrue(w.commands.isEmpty)
    }

    @MainActor func testBothSnapshotsAreRequiredAndForeignStopRejected() async throws {
        let x = OwnedSlotFixture(.rustXray), w = OwnedSlotFixture(.standaloneAWG)
        let d = try OwnedTransportDispatcher(xray: x, awg: w)
        XCTAssertThrowsError(try OwnedTransportDispatcher(xray: w, awg: x))
        w.idle = false
        var m = TransportBackendCoordinator()
        let command = try m.begin(plan(.wireGuard))
        guard case .start(let current) = command else { return XCTFail() }
        XCTAssertThrowsError(try d.submit(command))
        XCTAssertEqual(x.snapshots, 1); XCTAssertEqual(w.snapshots, 1)
        XCTAssertTrue(x.commands.isEmpty)
        XCTAssertThrowsError(try d.submit(.stop(current)))
        w.idle = true
        try d.submit(command)
        var foreign = TransportBackendCoordinator()
        guard case .start(let other) = try foreign.begin(plan(.wireGuard)) else { return XCTFail() }
        XCTAssertThrowsError(try d.submit(.cancelTunnel(other)))
        XCTAssertEqual(x.commands, [.start(current)])
    }

    @MainActor func testUnknownSnapshotAndReplayCannotStartProvider() async throws {
        let x = OwnedSlotFixture(.rustXray), w = OwnedSlotFixture(.standaloneAWG)
        let d = try OwnedTransportDispatcher(xray: x, awg: w)
        var m = TransportBackendCoordinator()
        let command = try m.begin(plan(.wireGuard))
        w.snapshotError = true
        XCTAssertThrowsError(try d.submit(command))
        XCTAssertTrue(x.commands.isEmpty)
        w.snapshotError = false
        try d.submit(command)
        x.idle = true
        XCTAssertThrowsError(try d.submit(command)) { error in
            XCTAssertEqual(error as? OwnedTransportDispatchError, .staleStart)
        }
        XCTAssertEqual(x.commands, [command])
    }

}
