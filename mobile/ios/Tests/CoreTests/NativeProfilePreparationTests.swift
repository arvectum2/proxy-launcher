import Foundation
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativeProfilePreparationTests: XCTestCase {
    private func source(awg: Bool = false) -> String {
        let local = Data(repeating:17,count:32).base64EncodedString()
        let remote = Data(repeating:34,count:32).base64EncodedString()
        let extra = awg ? "Jc=0\nJmin=0\nJmax=0\nS1=15\nS2=18\nH1=123456\nH2=67543\nH3=123123\nH4=32345" : ""
        return """
        [Interface]
        PrivateKey = \(local)
        Address = 10.0.0.2/32, fd00::2/128
        DNS = 192.0.2.53
        MTU = 1280
        \(extra)
        [Peer]
        PublicKey = \(remote)
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = 192.0.2.42:51820
        """
    }
    @MainActor private func prepare(_ p: NativeProfilePreparation, _ r: NativeProfilePreparation.Revision) throws -> NativeProfilePreparation.Ticket {
        try p.select(r)
        return try p.prepare(r,routes:.tunnelOnly,siteExclusions:[],applicationExclusions:[])
    }
    @MainActor func testSingleUseHandoffAndExactProvider() async throws {
        let p = NativeProfilePreparation(legacyIDs:{[]})
        for awg in [false,true] {
            let r = try p.stage(profileID:UUID(),expected:awg ? .amneziaWG1 : .wireGuard,source:source(awg:awg))
            let ticket = try prepare(p,r)
            let provider: TransportProvider = awg ? .standaloneAWG : .rustXray
            try p.consumeForValidation(ticket,provider:provider) { route, data in
                XCTAssertEqual(route.provider,provider); XCTAssertEqual(route.remoteAddress,"192.0.2.42"); XCTAssertFalse(data.isEmpty)
            }
            XCTAssertThrowsError(try p.consumeForValidation(ticket,provider:provider) { _,_ in XCTFail("replayed") })
        }
    }
    @MainActor func testRevisionReplacementAndSelectionInvalidate() async throws {
        let p = NativeProfilePreparation(legacyIDs:{[]}), id = UUID()
        let r = try p.stage(profileID:id,expected:.wireGuard,source:source())
        let t = try prepare(p,r)
        let revised = try p.stage(profileID:id,expected:.wireGuard,source:source())
        XCTAssertNotEqual(r,revised); XCTAssertThrowsError(try p.select(r))
        XCTAssertThrowsError(try p.consumeForValidation(t,provider:.rustXray) { _,_ in XCTFail("old revision") })
        let fresh = try prepare(p,revised)
        let other = try p.stage(profileID:UUID(),expected:.amneziaWG1,source:source(awg:true))
        try p.select(other)
        XCTAssertThrowsError(try p.consumeForValidation(fresh,provider:.rustXray) { _,_ in XCTFail("wrong selected profile") })
    }
    @MainActor func testFailedEditAtomicAndWrongProviderConsumes() async throws {
        let p = NativeProfilePreparation(legacyIDs:{[]}), id = UUID()
        let r = try p.stage(profileID:id,expected:.wireGuard,source:source())
        XCTAssertThrowsError(try p.stage(profileID:id,expected:.amneziaWG1,source:source()))
        let t = try prepare(p,r)
        XCTAssertThrowsError(try p.consumeForValidation(t,provider:.standaloneAWG) { _,_ in XCTFail("wrong provider") })
        XCTAssertThrowsError(try p.consumeForValidation(t,provider:.rustXray) { _,_ in XCTFail("retry") })
    }
    @MainActor func testLegacyCollisionAndReadFailure() async throws {
        var legacy = Set<UUID>(), corrupt = false
        enum ReadFailure: Error { case corrupt }
        let p = NativeProfilePreparation(legacyIDs:{ if corrupt { throw ReadFailure.corrupt }; return legacy })
        let id = UUID(), r = try p.stage(profileID:id,expected:.wireGuard,source:source())
        let t = try prepare(p,r); legacy.insert(id)
        XCTAssertThrowsError(try p.consumeForValidation(t,provider:.rustXray) { _,_ in XCTFail("collision") })
        XCTAssertThrowsError(try p.stage(profileID:id,expected:.wireGuard,source:source()))
        legacy.remove(id); corrupt = true
        XCTAssertThrowsError(try p.select(r))
        XCTAssertThrowsError(try p.stage(profileID:UUID(),expected:.wireGuard,source:source()))
    }
    @MainActor func testRejectedPolicyAndDeletionInvalidateTickets() async throws {
        let p = NativeProfilePreparation(legacyIDs:{[]}), r = try p.stage(profileID:UUID(),expected:.wireGuard,source:source())
        let t = try prepare(p,r)
        XCTAssertThrowsError(try p.prepare(r,routes:.tunnelOnly,siteExclusions:["example.invalid"],applicationExclusions:[]))
        XCTAssertThrowsError(try p.consumeForValidation(t,provider:.rustXray) { _,_ in XCTFail("old policy") })
        let fresh = try prepare(p,r); p.remove(profileID:r.profileID)
        XCTAssertThrowsError(try p.consumeForValidation(fresh,provider:.rustXray) { _,_ in XCTFail("deleted") })
        XCTAssertThrowsError(try p.select(r))
    }
    @MainActor func testBoundedInMemoryStagingAndReplacement() async throws {
        let p = NativeProfilePreparation(legacyIDs:{[]}), ids = (0..<32).map { _ in UUID() }
        for id in ids { try p.stage(profileID:id,expected:.wireGuard,source:source()) }
        XCTAssertThrowsError(try p.stage(profileID:UUID(),expected:.wireGuard,source:source()))
        let replacement = try p.stage(profileID:ids[0],expected:.wireGuard,source:source())
        let ticket = try prepare(p,replacement)
        try p.consumeForValidation(ticket,provider:.rustXray) { _,_ in }
        p.remove(profileID:ids[1]); try p.stage(profileID:UUID(),expected:.wireGuard,source:source())
    }
    @MainActor func testTicketCannotBeUsedAcrossPreparationInstances() async throws {
        let a = NativeProfilePreparation(legacyIDs:{[]}), b = NativeProfilePreparation(legacyIDs:{[]}), id = UUID()
        let r = try a.stage(profileID:id,expected:.wireGuard,source:source())
        let t = try prepare(a,r)
        let other = try b.stage(profileID:id,expected:.wireGuard,source:source())
        let fresh = try prepare(b,other)
        XCTAssertThrowsError(try b.consumeForValidation(t,provider:.rustXray) { _,_ in XCTFail("foreign ticket") })
        try b.consumeForValidation(fresh,provider:.rustXray) { _,_ in }
    }
    @MainActor func testConsumerFailureAndClear() async throws {
        enum ProbeError:Error {case failed}
        let p = NativeProfilePreparation(legacyIDs:{[]}), r = try p.stage(profileID:UUID(),expected:.wireGuard,source:source())
        let t = try prepare(p,r)
        XCTAssertThrowsError(try p.consumeForValidation(t,provider:.rustXray) { _,_ in throw ProbeError.failed })
        XCTAssertThrowsError(try p.consumeForValidation(t,provider:.rustXray) { _,_ in XCTFail("retried") })
        let fresh = try prepare(p,r);p.clear()
        XCTAssertThrowsError(try p.consumeForValidation(fresh,provider:.rustXray) { _,_ in XCTFail("cleared") })
    }
}
