import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativeProductManagerPreflightTests: XCTestCase {
    typealias Gate = NativeProductManagerPreflight

    func testReadbackPermitsOnlySingleOwnedInvalidProductManager() {
        XCTAssertTrue(Gate.permitsReadback([.disconnected, .invalid], ownedProductIndex:1))
        XCTAssertTrue(Gate.permitsReadback([.disconnected], ownedProductIndex:nil))
        XCTAssertFalse(Gate.permitsReadback([.disconnected, .invalid], ownedProductIndex:nil))
        XCTAssertFalse(Gate.permitsReadback([.invalid, .disconnected], ownedProductIndex:1))
        XCTAssertFalse(Gate.permitsReadback([.invalid, .invalid], ownedProductIndex:1))
        XCTAssertFalse(Gate.permitsReadback([.activeOrUnknown], ownedProductIndex:0))
        XCTAssertFalse(Gate.permitsReadback([.disconnected, .activeOrUnknown], ownedProductIndex:1))
    }

    func testLaunchNeverAcceptsInvalidOrActiveManager() {
        XCTAssertTrue(Gate.permitsLaunch([]))
        XCTAssertTrue(Gate.permitsLaunch([.disconnected,.disconnected]))
        XCTAssertFalse(Gate.permitsLaunch([.invalid]))
        XCTAssertFalse(Gate.permitsLaunch([.disconnected,.invalid]))
        XCTAssertFalse(Gate.permitsLaunch([.activeOrUnknown]))
    }
}
