import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class QuickVPNActionPolicyTests: XCTestCase {
    func testConnectIsIdempotentDuringActiveConnection() {
        XCTAssertEqual(QuickVPNActionPolicy.decide(action: .connect, state: .connected), .noChange)
        XCTAssertEqual(QuickVPNActionPolicy.decide(action: .connect, state: .connecting), .noChange)
        XCTAssertEqual(QuickVPNActionPolicy.decide(action: .connect, state: .disconnected), .connect)
    }
    func testDisconnectAndToggleBehaveAsUserRequested() {
        XCTAssertEqual(QuickVPNActionPolicy.decide(action: .disconnect, state: .connected), .disconnect)
        XCTAssertEqual(QuickVPNActionPolicy.decide(action: .disconnect, state: .disconnected), .noChange)
        XCTAssertEqual(QuickVPNActionPolicy.decide(action: .toggle, state: .connected), .disconnect)
        XCTAssertEqual(QuickVPNActionPolicy.decide(action: .toggle, state: .disconnected), .connect)
    }
    func testDisconnectingIsFailClosedAndNeverImplicitlyToggled() {
        for action in QuickVPNAction.allCases {
            XCTAssertEqual(QuickVPNActionPolicy.decide(action: action, state: .disconnecting), .busy)
        }
    }
}
