import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativeDomainPolicyReviewTests:XCTestCase {
    private let now=Date(timeIntervalSince1970:1_800_000_000)
    func testPreservesManualCuratedAndLegacyOnlyIntentWithoutAdmission()throws {
        let result=try NativeDomainPolicyReview.inspect(manual:["www.gosuslugi.ru","198.51.100.7"],legacy:["www.gosuslugi.ru","old.example.test"],graph:nil,mode:"normallyOn",at:now)
        XCTAssertEqual(result.admission,.siteExclusions);XCTAssertFalse(result.nativeDomainRoutesAvailable)
        XCTAssertEqual(result.rows.first{$0.host=="198.51.100.7"}?.source,.manual)
        XCTAssertEqual(result.rows.first{$0.host=="gu-st.ru"}?.source,.derivedAlias)
        XCTAssertEqual(result.rows.first{$0.host=="gosuslugi.ru"}?.source,.derivedAlias)
        XCTAssertEqual(result.rows.first{$0.host=="old.example.test"}?.source,.legacyOnly)
        XCTAssertFalse(result.rows.contains{$0.host=="www.198.51.100.7"})
    }
    func testDiscoveryDecisionsAndTombstonesRemainSeparate()throws {
        var g=SmartExclusionGraph()
        try g.observe(parent:"example.test",html:["api.example.test","analytics.example.test","stale.example.test","removed.example.test","deny.example.test"],network:["api.example.test","analytics.example.test"],at:now)
        _=g.approveStrongFirstParty(parent:"example.test",manual:["example.test"],at:now)
        try g.set(.approved,parent:"example.test",child:"stale.example.test")
        try g.set(.rejected,parent:"example.test",child:"deny.example.test")
        g.remove(parent:"example.test",child:"removed.example.test")
        try g.addUserLink(parent:"other.test",child:"login.partner.test",at:now)
        g.edges[g.edges.firstIndex{$0.host=="stale.example.test"}!].lastSeen=now.addingTimeInterval(-SmartExclusionGraph.ttl-1)
        let bytes=try JSONEncoder().encode(g)
        let result=try NativeDomainPolicyReview.inspect(manual:["example.test"],legacy:nil,graph:bytes,mode:"normallyOn",at:now)
        let rows=result.rows.filter{$0.source == .dependency};let statuses=Dictionary(uniqueKeysWithValues:rows.map{($0.host,$0.status)})
        XCTAssertEqual(statuses["api.example.test"],.approved);XCTAssertEqual(statuses["analytics.example.test"],.pending)
        XCTAssertEqual(statuses["stale.example.test"],.expired);XCTAssertEqual(statuses["removed.example.test"],.suppressed)
        XCTAssertEqual(statuses["deny.example.test"],.rejected);XCTAssertEqual(statuses["login.partner.test"],.orphaned)
        XCTAssertEqual(try JSONDecoder().decode(SmartExclusionGraph.self,from:bytes),g)
        XCTAssertFalse(result.nativeDomainRoutesAvailable);XCTAssertFalse(result.admission.permitsSelection)
    }
    func testDuplicatesNeverShownAsCleanApprovalAndMalformedFails()throws {
        var g=SmartExclusionGraph();try g.observe(parent:"example.test",html:["api.example.test"],network:[],at:now)
        try g.set(.approved,parent:"example.test",child:"api.example.test");g.edges += g.edges
        let result=try NativeDomainPolicyReview.inspect(manual:["example.test"],legacy:nil,graph:JSONEncoder().encode(g),mode:"normallyOff",at:now)
        XCTAssertTrue(result.normallyOff);XCTAssertEqual(result.admission,.normallyOff)
        XCTAssertEqual(result.rows.first{$0.host=="api.example.test"}?.status,.ambiguous)
        for bad:Any in ["not a graph",Data([1,2,3])] {XCTAssertThrowsError(try NativeDomainPolicyReview.inspect(manual:nil,legacy:nil,graph:bad,mode:nil,at:now))}
        XCTAssertThrowsError(try NativeDomainPolicyReview.inspect(manual:["example.test"],legacy:nil,graph:nil,mode:"unknown",at:now))
    }
}
