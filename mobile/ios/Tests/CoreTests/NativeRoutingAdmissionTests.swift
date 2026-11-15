import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativeRoutingAdmissionTests:XCTestCase {
    func testStoredPoliciesNeverSilentlyBecomeTunnelOnly()throws {
        func check(_ manual:Any?=nil,_ legacy:Any?=nil,_ graph:Any?=nil,_ mode:Any?=nil)->NativeRoutingAdmission {NativeRoutingAdmission.inspect(manual:manual,legacy:legacy,graph:graph,mode:mode)}
        XCTAssertEqual(check(),.tunnelOnly)
        XCTAssertEqual(check([],[],nil,"normallyOn"),.tunnelOnly)
        XCTAssertEqual(check(["example.com"],[]),.siteExclusions)
        XCTAssertEqual(check([], ["192.0.2.2"]),.siteExclusions)
        XCTAssertEqual(check(nil,nil,nil,"normallyOff"),.normallyOff)
        XCTAssertEqual(check("invalid"),.malformed);XCTAssertEqual(check(nil,nil,Data([0])),.malformed)
        XCTAssertEqual(check(nil,nil,nil,"unknown"),.malformed)
        var graph=SmartExclusionGraph();graph.edges=[.init(parent:"example.com",host:"cdn.example.com",evidence:.html,decision:.approved,lastSeen:Date(timeIntervalSince1970:1))]
        XCTAssertEqual(check(nil,nil,try JSONEncoder().encode(graph)),.dependencyPolicy)
        graph.edges[0].decision = .pending
        XCTAssertEqual(check(nil,nil,try JSONEncoder().encode(graph)),.tunnelOnly)
    }
}
