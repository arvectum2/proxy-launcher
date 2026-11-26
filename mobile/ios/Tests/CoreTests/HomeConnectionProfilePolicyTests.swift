import XCTest
@testable import ArvectumProxyLauncherIOSCore
final class HomeConnectionProfilePolicyTests:XCTestCase {
    func testNativeOnlySelectionUsesConnectRatherThanAdd() {
        XCTAssertTrue(HomeConnectionProfilePolicy.hasTarget(legacyCount:0,nativeSelectionPresent:true))
        XCTAssertFalse(HomeConnectionProfilePolicy.offersAdd(legacyCount:0,nativeSelectionPresent:true,active:false))
    }
    func testEmptyLegacyAndNativeOffersAddOnlyWhenOff() {
        XCTAssertFalse(HomeConnectionProfilePolicy.hasTarget(legacyCount:0,nativeSelectionPresent:false))
        XCTAssertTrue(HomeConnectionProfilePolicy.offersAdd(legacyCount:0,nativeSelectionPresent:false,active:false))
        XCTAssertFalse(HomeConnectionProfilePolicy.offersAdd(legacyCount:0,nativeSelectionPresent:false,active:true))
    }
    func testLegacyAndPreviewKeepExistingConnectAction() {
        XCTAssertFalse(HomeConnectionProfilePolicy.offersAdd(legacyCount:1,nativeSelectionPresent:false,active:false))
        XCTAssertFalse(HomeConnectionProfilePolicy.offersAdd(legacyCount:0,nativeSelectionPresent:false,preview:true,active:false))
    }
}
