import Foundation
import CryptoKit
import XCTest
@testable import ArvectumProxyLauncherIOSCore

private final class TestItems: NativeCredentialItems, @unchecked Sendable {
    private let lock = NSLock()
    enum Failure: Error { case duplicate, denied }
    var values: [String:Data] = [:]
    var denyRemoval = false
    func insert(account: String, bytes: Data) throws {
        lock.lock(); defer {lock.unlock()}
        guard values[account] == nil else {throw Failure.duplicate}; values[account] = bytes
    }
    func read(account: String) throws -> Data? { lock.lock(); defer {lock.unlock()}; return values[account] }
    func remove(account: String) throws -> Bool {
        lock.lock(); defer {lock.unlock()}
        if denyRemoval {throw Failure.denied}; return values.removeValue(forKey:account) != nil
    }
}

final class NativeCredentialHandoffTests: XCTestCase {
    private func fixture() throws -> (NativeCredentialRecord, NativeCredentialHandoff.Binding, NativeCredentialRepository, TestItems, TestItems) {
        let local = Curve25519.KeyAgreement.PrivateKey().rawRepresentation.base64EncodedString()
        let peer = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let source = ["[Interface]", "PrivateKey=\(local)", "Address=10.0.0.2/32, fd00::2/128", "DNS=192.0.2.53", "[Peer]", "PublicKey=\(peer)", "AllowedIPs=0.0.0.0/0, ::/0", "Endpoint=192.0.2.42:51820"].joined(separator:"\n")
        let r = try NativeCredentialRecord.create(profileID:UUID(),expected:.wireGuard,source:source)
        let b = NativeCredentialHandoff.Binding(reference:r.reference,session:.init(epoch:UUID(),generation:1,provider:"rust-xray"),selectionNonce:UUID())
        let store=TestItems(), tickets=TestItems(), repo=NativeCredentialRepository(items:store)
        return (r,b,repo,store,tickets)
    }
    func testRuntimeTicketIsDistinctAndBoundToScopedProbe() throws {
        let (r,b,repo,_,tickets)=try fixture()
        try repo.insert(r)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{$0==b}), owner=UUID()
        let legacy=try h.issue(r,binding:b)
        XCTAssertThrowsError(try NativeRuntimeReviewRequest.options(ticket:legacy,owner:owner))
        XCTAssertThrowsError(try h.redeem(legacy,expected:b,runtimeOwner:owner))
        XCTAssertTrue(try h.revoke(legacy))
        let ticket=try h.issue(r,binding:b,runtimeOwner:owner,runtimeProbeIPv4:"198.51.100.77")
        XCTAssertThrowsError(try h.redeem(ticket,expected:b))
        XCTAssertThrowsError(try NativeRuntimeReviewRequest.options(ticket:ticket,owner:UUID()))
        let config=NativeRuntimeReviewRequest.configuration(owner:owner)
        let options=try NativeRuntimeReviewRequest.options(ticket:ticket,owner:owner)
        XCTAssertNil(NativeRuntimeReviewRequest.inspect(configuration:config,options:options,enabled:false))
        let request=try XCTUnwrap(NativeRuntimeReviewRequest.inspect(configuration:config,options:options,enabled:true))
        XCTAssertThrowsError(try request.consume(via:h,admission:.siteExclusions))
        let plan=try request.consume(via:h,admission:.tunnelOnly)
        guard case .xray(let scope)=plan.route else{return XCTFail("unexpected route")}
        XCTAssertEqual(scope.localIPv4,"10.0.0.2");XCTAssertEqual(scope.targetIPv4,"198.51.100.77")
        XCTAssertEqual(scope.validation.remoteAddress,"192.0.2.42")
        XCTAssertThrowsError(try request.consume(via:h,admission:.tunnelOnly))
        let conflict=try h.issue(r,binding:b,runtimeOwner:owner,runtimeProbeIPv4:"192.0.2.42")
        let conflicting=try XCTUnwrap(NativeRuntimeReviewRequest.inspect(configuration:config,options:NativeRuntimeReviewRequest.options(ticket:conflict,owner:owner),enabled:true))
        XCTAssertThrowsError(try conflicting.consume(via:h,admission:.tunnelOnly))
    }
    func testExtendedRuntimeScopeRequiresExactDNSAndPreservesProfile() throws {
        let (r,b,repo,_,items)=try fixture()
        try repo.insert(r)
        let h=NativeCredentialHandoff(items:items,repository:repo,authorizes:{$0==b}),owner=UUID()
        let full=try h.issue(r,binding:b,runtimeOwner:owner,runtimeScope:.wireGuardFull)
        XCTAssertEqual(full.purpose,.runtimeDataPlaneReview)
        let request=try XCTUnwrap(NativeRuntimeReviewRequest.inspect(configuration:NativeRuntimeReviewRequest.configuration(owner:owner),options:NativeRuntimeReviewRequest.options(ticket:full,owner:owner),enabled:true))
        XCTAssertThrowsError(try request.consume(via:h,admission:.tunnelOnly))
        let result=try request.consume(via:h,admission:.tunnelOnly,exactDNSAvailable:true)
        guard case .xrayWireGuardFull(let route)=result.route else{return XCTFail("wrong full scope")}
        XCTAssertEqual(route.dnsServers,["192.0.2.53"]);XCTAssertEqual(route.ipv4Address,"10.0.0.2");XCTAssertEqual(route.ipv6Address,"fd00::2");XCTAssertTrue(route.excludedRoutes.isEmpty)
        let args=try XraySocksHandoffPlan.prepare(tunFD:3,socksPort:39879,dnsBypass:[],exactDNS:true)
        XCTAssertTrue(args.tun2proxyArguments.contains("--dns direct --native-exact-dns"))
        XCTAssertFalse(try XraySocksHandoffPlan.prepare(tunFD:3,socksPort:39879,dnsBypass:[]).tun2proxyArguments.contains("native-exact-dns"))
        let key=Data(repeating:17,count:32).base64EncodedString().replacingOccurrences(of:"=",with:"")
        let v=try NativeCredentialRecord.create(profileID:UUID(),expected:.vlessReality,source:"vless://12345678-abcd-abcd-abcd-123456789abc@192.0.2.42:443?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk="+key+"&sid=abcd")
        try repo.insert(v)
        let vb=NativeCredentialHandoff.Binding(reference:v.reference,session:.init(epoch:UUID(),generation:1,provider:"rust-xray"),selectionNonce:UUID())
        let vh=NativeCredentialHandoff(items:items,repository:repo,authorizes:{$0==vb})
        let t=try vh.issue(v,binding:vb,runtimeOwner:owner,runtimeProbeIPv4:"198.51.100.77",runtimeScope:.vlessDatagrams,runtimeProbeIPv6:"2001:db8::77")
        let rev=try XCTUnwrap(NativeRuntimeReviewRequest.inspect(configuration:NativeRuntimeReviewRequest.configuration(owner:owner),options:NativeRuntimeReviewRequest.options(ticket:t,owner:owner),enabled:true))
        XCTAssertThrowsError(try rev.consume(via:vh,admission:.tunnelOnly))
        let expanded=try rev.consume(via:vh,admission:.tunnelOnly,exactDNSAvailable:true)
        guard case .xray(let scope)=expanded.route else{return XCTFail("wrong VLESS scope")}
        XCTAssertEqual(scope.targetIPv4,"198.51.100.77");XCTAssertEqual(scope.targetIPv6,"2001:db8::77")
        func json(_ data:Data)throws->[String:Any]{try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])}
        let old=try json(v.compile().0.withEngineConfiguration{$0}),new=try json(expanded.configuration.withEngineConfiguration{$0})
        let inbound=try XCTUnwrap((new["inbounds"] as? [[String:Any]])?.first)
        XCTAssertEqual((inbound["settings"] as? [String:Any])?["udp"] as? Bool,true)
        XCTAssertEqual((old["outbounds"] as? NSArray),(new["outbounds"] as? NSArray))
        XCTAssertEqual((old["routing"] as? NSDictionary),(new["routing"] as? NSDictionary))
        XCTAssertThrowsError(try rev.consume(via:vh,admission:.tunnelOnly,exactDNSAvailable:true))
    }
    func testImmutableStorageAndReference() throws {
        let (r,_,repo,store,_) = try fixture()
        XCTAssertNil(try repo.read(r.reference)); try repo.insert(r)
        XCTAssertThrowsError(try repo.insert(r)); XCTAssertEqual(try repo.read(r.reference)?.encoded(),try r.encoded())
        let other = try fixture().0.reference
        XCTAssertThrowsError(try NativeCredentialRecord.decode(r.encoded(),expected:other))
        XCTAssertTrue(try repo.remove(r.reference)); XCTAssertFalse(try repo.remove(r.reference)); XCTAssertTrue(store.values.isEmpty)
        XCTAssertEqual(Mirror(reflecting:r).children.count,0)
    }
    func testOneUseMetadataOnlyTicket() throws {
        let (r,b,repo,_,tickets) = try fixture(); let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{ $0.reference == r.reference })
        XCTAssertThrowsError(try h.issue(r,binding:b));try repo.insert(r)
        let t=try h.issue(r,binding:b)
        let bytes=try XCTUnwrap(tickets.values.values.first)
        let fields=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        XCTAssertEqual(Set(fields.keys),["version","ticket","issued","expires"])
        XCTAssertEqual(try h.redeem(t,expected:b).reference,r.reference)
        XCTAssertThrowsError(try h.redeem(t,expected:b)); XCTAssertTrue(tickets.values.isEmpty)
    }
    func testWrongSessionAndDeletedRevision() throws {
        let (r,b,repo,_,tickets)=try fixture();try repo.insert(r)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{ $0.reference == r.reference }), t=try h.issue(r,binding:b)
        let other=NativeCredentialHandoff.Binding(reference:r.reference,session:.init(epoch:UUID(),generation:1,provider:"rust-xray"),selectionNonce:UUID())
        XCTAssertThrowsError(try h.redeem(t,expected:other)); XCTAssertEqual(tickets.values.count,1)
        let wrong=NativeCredentialHandoff.Binding(reference:r.reference,session:.init(epoch:b.session.epoch,generation:1,provider:"standalone-awg"),selectionNonce:UUID())
        XCTAssertThrowsError(try h.issue(r,binding:wrong));try repo.remove(r.reference)
        XCTAssertThrowsError(try h.redeem(t,expected:b));XCTAssertTrue(tickets.values.isEmpty)
    }
    func testExpiryClockRollbackAndRevocation() throws {
        let (r,b,repo,_,tickets)=try fixture();try repo.insert(r)
        let start=Date(timeIntervalSince1970:1000);var time=start
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{ $0.reference == r.reference },now:{time})
        for offset in [60.0,-1.0] {
            time=start;let t=try h.issue(r,binding:b);time=start.addingTimeInterval(offset)
            XCTAssertThrowsError(try h.redeem(t,expected:b));XCTAssertTrue(tickets.values.isEmpty)
        }
        time=start;let t=try h.issue(r,binding:b);XCTAssertTrue(try h.revoke(t));XCTAssertThrowsError(try h.redeem(t,expected:b))
    }
    func testCleanupOnlyExpiredExactTicketsAndLeavesRevision() throws {
        let (r,b,repo,store,tickets)=try fixture();try repo.insert(r)
        var time=Date(timeIntervalSince1970:1000)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{ $0.reference == r.reference },now:{time})
        let expired=try h.issue(r,binding:b);time.addTimeInterval(30)
        let active=try h.issue(r,binding:b),vanished=try h.issue(r,binding:b)
        try h.revoke(vanished);time.addTimeInterval(30)
        let bad="handoff-v1/"+UUID().uuidString
        try tickets.insert(account:bad,bytes:Data([1]))
        let names=[expired,active,vanished].map{"handoff-v1/"+$0.id.uuidString}+[bad]
        XCTAssertEqual(try h.cleanupExpired(accounts:names),.init(removed:1,retained:1,disappeared:1,malformed:1))
        XCTAssertThrowsError(try h.redeem(expired,expected:b))
        XCTAssertEqual(try h.redeem(active,expected:b).reference,r.reference)
        XCTAssertEqual(tickets.values.count,1);XCTAssertEqual(store.values.count,1)
        XCTAssertEqual(try h.cleanupExpired(accounts:names),.init(removed:0,retained:0,disappeared:3,malformed:1))
    }
    func testCleanupRejectsInvalidBatchBeforeMutationAndClockRollback() throws {
        let (r,b,repo,_,tickets)=try fixture();try repo.insert(r)
        var time=Date(timeIntervalSince1970:1000)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{_ in true},now:{time})
        let t=try h.issue(r,binding:b),name="handoff-v1/"+t.id.uuidString
        time.addTimeInterval(-1)
        XCTAssertEqual(try h.cleanupExpired(accounts:[name]).retained,1)
        time.addTimeInterval(61)
        for batch in [[name,"record-v1/"+UUID().uuidString],[name,name],(0..<65).map{_ in "handoff-v1/"+UUID().uuidString}] {
            XCTAssertThrowsError(try h.cleanupExpired(accounts:batch));XCTAssertEqual(tickets.values.count,1)
        }
        tickets.denyRemoval=true;XCTAssertThrowsError(try h.cleanupExpired(accounts:[name]));XCTAssertEqual(tickets.values.count,1)
        tickets.denyRemoval=false;XCTAssertEqual(try h.cleanupExpired(accounts:[name]).removed,1)
    }
    func testCleanupAndExpiredRedemptionRaceCannotReturnCredential() throws {
        let (r,b,repo,store,tickets)=try fixture();try repo.insert(r)
        let start=Date(timeIntervalSince1970:1000)
        let issuer=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{_ in true},now:{start})
        let t=try issuer.issue(r,binding:b),name="handoff-v1/"+t.id.uuidString
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{_ in true},now:{start.addingTimeInterval(60)})
        let unexpected=TestItems()
        DispatchQueue.concurrentPerform(iterations:16){ i in
            if i.isMultiple(of:2) { _=try? h.cleanupExpired(accounts:[name]) }
            else if (try? h.redeem(t,expected:b)) != nil {try? unexpected.insert(account:String(i),bytes:Data([1]))}
        }
        XCTAssertTrue(unexpected.values.isEmpty);XCTAssertTrue(tickets.values.isEmpty);XCTAssertEqual(store.values.count,1)
    }
    func testCleanupDoesNotSweepMetadataUnderWrongAccount() throws {
        let (r,b,repo,_,tickets)=try fixture();try repo.insert(r)
        let start=Date(timeIntervalSince1970:1000)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{_ in true},now:{start})
        let t=try h.issue(r,binding:b),name="handoff-v1/"+t.id.uuidString,other="handoff-v1/"+UUID().uuidString
        try tickets.insert(account:other,bytes:XCTUnwrap(tickets.read(account:name)))
        let cleanup=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{_ in true},now:{start.addingTimeInterval(60)})
        XCTAssertEqual(try cleanup.cleanupExpired(accounts:[other,name]),.init(removed:1,retained:0,disappeared:0,malformed:1))
        XCTAssertNotNil(try tickets.read(account:other))
    }
    func testDeletionFailureNeverReturnsRecord() throws {
        let (r,b,repo,_,tickets)=try fixture();try repo.insert(r)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{ $0.reference == r.reference }),t=try h.issue(r,binding:b)
        tickets.denyRemoval=true;XCTAssertThrowsError(try h.redeem(t,expected:b));tickets.denyRemoval=false
        XCTAssertEqual(try h.redeem(t,expected:b).reference,r.reference)
    }
    func testConcurrentConsumersOnlyOneWins() throws {
        let (r,b,repo,_,tickets)=try fixture();try repo.insert(r)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{ $0.reference == r.reference }),t=try h.issue(r,binding:b)
        let winners=TestItems()
        DispatchQueue.concurrentPerform(iterations:16) { i in
            if (try? h.redeem(t,expected:b)) != nil { try? winners.insert(account:String(i),bytes:Data([1])) }
        }
        XCTAssertEqual(winners.values.count,1); XCTAssertTrue(tickets.values.isEmpty)
    }
    func testProviderReceiverConsumesExactlyOnce() throws {
        let (r,b,repo,_,tickets)=try fixture();try repo.insert(r)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{$0.reference == r.reference})
        let t=try h.issue(r,binding:b), bytes=try TransportNativeCodec.encode(t)
        var receiver=try NativeCredentialReceiver(expected:b,provider:.rustXray)
        try receiver.consumeForValidation(bytes,via:h) { route,data in
            XCTAssertEqual(route.provider,.rustXray); XCTAssertFalse(data.isEmpty)
        }
        XCTAssertThrowsError(try receiver.consumeForValidation(bytes,via:h) { _,_ in XCTFail("replay") })
        var fresh=try NativeCredentialReceiver(expected:b,provider:.rustXray)
        XCTAssertThrowsError(try fresh.consumeForValidation(bytes,via:h) { _,_ in XCTFail("store replay") })
    }
    func testReceiverIndependentIdentityAndFailurePoisoning() throws {
        let (r,b,repo,_,tickets)=try fixture();try repo.insert(r)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{$0.reference == r.reference})
        let t=try h.issue(r,binding:b),bytes=try TransportNativeCodec.encode(t)
        let other=NativeCredentialHandoff.Binding(reference:r.reference,session:.init(epoch:b.session.epoch,generation:2,provider:"rust-xray"),selectionNonce:UUID())
        XCTAssertThrowsError(try NativeCredentialReceiver(expected:b,provider:.standaloneAWG))
        var wrong=try NativeCredentialReceiver(expected:other,provider:.rustXray)
        XCTAssertThrowsError(try wrong.consumeForValidation(bytes,via:h) { _,_ in XCTFail("stale") })
        var receiver=try NativeCredentialReceiver(expected:b,provider:.rustXray)
        XCTAssertThrowsError(try receiver.consumeForValidation(Data(repeating:0,count:1025),via:h) { _,_ in XCTFail("invalid") })
        XCTAssertThrowsError(try receiver.consumeForValidation(bytes,via:h) { _,_ in XCTFail("retry after failure") })
        XCTAssertEqual(tickets.values.count,1)
    }
    private func vlessSource(_ host: String = "192.0.2.42") -> String {
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        return "vless://\(UUID().uuidString.lowercased())@\(host):443?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk=\(key)&sid=abcd&flow=xtls-rprx-vision#Synthetic"
    }
    @MainActor func testVLESSCatalogAndProviderHandoff() async throws {
        let (_,_,repo,_,tickets)=try fixture()
        let source=vlessSource(),record=try NativeCredentialRecord.create(profileID:UUID(),expected:.vlessReality,source:source)
        let p=NativeProfilePreparation(legacyIDs:{[]}), rev=try p.stage(record);try p.retainRevision(rev,in:repo)
        let restored=try XCTUnwrap(repo.read(record.reference));XCTAssertEqual(restored.reference,record.reference)
        let p2=NativeProfilePreparation(legacyIDs:{[]}), r=try p2.stage(restored);XCTAssertEqual(r,rev);try p2.select(r)
        let t=try p2.prepare(r,routes:.tunnelOnly,siteExclusions:[],applicationExclusions:[])
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{$0.reference == record.reference})
        let binding=NativeCredentialHandoff.Binding(reference:record.reference,session:.init(epoch:UUID(),generation:1,provider:"rust-xray"),selectionNonce:UUID())
        let ticket=try p2.issueForValidation(t,binding:binding,via:h)
        var receiver=try NativeCredentialReceiver(expected:binding,provider:.rustXray)
        try receiver.consumeForValidation(TransportNativeCodec.encode(ticket),via:h) { route,bytes in
            guard case .vlessTCP4(let plan)=route else {XCTFail("WG route inherited");return}
            XCTAssertEqual(plan.required,[.tcpIPv4]);XCTAssertEqual(plan.remoteAddress,"192.0.2.42");XCTAssertEqual(plan.remotePort,443)
            let root=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
            let outbound=try XCTUnwrap(root["outbounds"] as? [[String:Any]])
            XCTAssertEqual(outbound.count,1);XCTAssertEqual(outbound[0]["protocol"] as? String,"vless")
            let inbound=try XCTUnwrap(root["inbounds"] as? [[String:Any]])
            XCTAssertEqual((inbound[0]["settings"] as? [String:Any])?["udp"] as? Bool,false);XCTAssertNil(root["dns"])
        }
        XCTAssertThrowsError(try TransportBackendPlan.prepare(profileID:r.profileID,revision:r.revision,protocol:.vlessReality,scope:.production,routes:.tunnelOnly,required:[.tcpIPv4]))
        XCTAssertThrowsError(try TransportBackendPlan.prepare(profileID:r.profileID,revision:r.revision,protocol:.vlessReality,scope:.syntheticLab,routes:.tunnelOnly,required:[.dns]))
    }
    func testVLESSUnsupportedEndpointsAndFormat() throws {
        for host in ["example.com","127.0.0.1","0.0.0.0","169.254.1.1","224.1.2.3","[2001:db8::2]"] {
            XCTAssertThrowsError(try NativeCredentialRecord.create(profileID:UUID(),expected:.vlessReality,source:vlessSource(host)))
        }
        XCTAssertThrowsError(try NativeCredentialRecord.create(profileID:UUID(),expected:.wireGuard,source:vlessSource()))
        XCTAssertThrowsError(try NativeCredentialRecord.create(profileID:UUID(),expected:.vlessReality,source:vlessSource()+"\n"+vlessSource()))
    }
    func testSameProviderDoesNotAuthorizeDifferentProtocol() throws {
        let (wg,b,repo,_,tickets)=try fixture();try repo.insert(wg)
        let v=try NativeCredentialRecord.create(profileID:wg.reference.profileID,expected:.vlessReality,source:vlessSource());try repo.insert(v)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{_ in true}),t=try h.issue(wg,binding:b)
        let wrong=NativeCredentialHandoff.Binding(reference:v.reference,session:b.session,selectionNonce:b.selectionNonce)
        var receiver=try NativeCredentialReceiver(expected:wrong,provider:.rustXray)
        XCTAssertThrowsError(try receiver.consumeForValidation(TransportNativeCodec.encode(t),via:h){_,_ in XCTFail("wrong protocol")})
        XCTAssertEqual(try h.redeem(t,expected:b).reference,wg.reference)
    }
    @MainActor func testPreparationPersistenceAndHandoff() async throws {
        let (r,b,repo,_,tickets)=try fixture()
        let p=NativeProfilePreparation(legacyIDs:{[]}), r1=try p.stage(r);try p.retainRevision(r1,in:repo)
        let restored=try XCTUnwrap(repo.read(r.reference)), p2=NativeProfilePreparation(legacyIDs:{[]}), r2=try p2.stage(restored)
        XCTAssertEqual(r1,r2);try p2.select(r2)
        let local=try p2.prepare(r2,routes:.tunnelOnly,siteExclusions:[],applicationExclusions:[])
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{ $0.reference == r.reference }), t=try p2.issueForValidation(local,binding:b,via:h)
        XCTAssertThrowsError(try p2.issueForValidation(local,binding:b,via:h));XCTAssertEqual(try h.redeem(t,expected:b).reference,r.reference)
    }
}
