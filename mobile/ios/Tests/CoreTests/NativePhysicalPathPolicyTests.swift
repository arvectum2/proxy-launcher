import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativePhysicalPathPolicyTests:XCTestCase {
    typealias Policy=NativePhysicalPathPolicy
    private let wifi=Policy.Signature(satisfied:true,interfaces:["en0:wifi:true"],expensive:false,constrained:false)
    private let cell=Policy.Signature(satisfied:true,interfaces:["pdp_ip0:cellular:true"],expensive:true,constrained:false)

    func testUniquePhysicalInterface() {
        XCTAssertEqual(Policy.uniqueInterface(satisfied:true,eligibleNames:["en0"]),"en0")
        XCTAssertEqual(Policy.uniqueInterface(satisfied:true,eligibleNames:["pdp_ip0"]),"pdp_ip0")
        XCTAssertEqual(Policy.uniqueInterface(satisfied:true,eligibleNames:["en0","en0"]),"en0")
        XCTAssertNil(Policy.uniqueInterface(satisfied:true,eligibleNames:[]))
        XCTAssertNil(Policy.uniqueInterface(satisfied:true,eligibleNames:["en0","pdp_ip0"]))
        XCTAssertNil(Policy.uniqueInterface(satisfied:false,eligibleNames:["en0"]))
    }

    func testStablePathAndOrderIndependentSignature() {
        var session=Policy.Session()
        let first=Policy.Signature(satisfied:true,interfaces:["en0:wifi:true","pdp_ip0:cellular:false"],expensive:false,constrained:false)
        let reordered=Policy.Signature(satisfied:true,interfaces:["pdp_ip0:cellular:false","en0:wifi:true"],expensive:false,constrained:false)
        XCTAssertTrue(session.observe(first))
        XCTAssertTrue(session.observe(reordered))
        XCTAssertFalse(session.revoked)
    }

    func testWiFiToCellularRequiresNewSession() {
        var session=Policy.Session()
        XCTAssertTrue(session.observe(wifi))
        XCTAssertFalse(session.observe(cell))
        XCTAssertTrue(session.revoked)
        XCTAssertFalse(session.observe(wifi))
        var next=Policy.Session()
        XCTAssertTrue(next.observe(cell))
        XCTAssertFalse(next.observe(wifi))
        XCTAssertFalse(next.observe(cell))
    }

    func testUnsatisfiedPathRevocationIsSticky() {
        let down=Policy.Signature(satisfied:false,interfaces:[],expensive:false,constrained:false)
        var session=Policy.Session()
        XCTAssertFalse(session.observe(down))
        XCTAssertFalse(session.observe(wifi))
        var established=Policy.Session()
        XCTAssertTrue(established.observe(wifi))
        XCTAssertFalse(established.observe(down))
        XCTAssertFalse(established.observe(wifi))
    }

    func testInterfaceAndCostChangesRevoke() {
        for changed in [
            Policy.Signature(satisfied:true,interfaces:["en1:wifi:true"],expensive:false,constrained:false),
            Policy.Signature(satisfied:true,interfaces:["en0:wifi:true","pdp_ip0:cellular:false"],expensive:false,constrained:false),
            Policy.Signature(satisfied:true,interfaces:["en0:wifi:true"],expensive:true,constrained:false),
            Policy.Signature(satisfied:true,interfaces:["en0:wifi:true"],expensive:false,constrained:true)
        ] {
            var session=Policy.Session()
            XCTAssertTrue(session.observe(wifi))
            XCTAssertFalse(session.observe(changed))
            XCTAssertFalse(session.observe(wifi))
        }
    }
}
