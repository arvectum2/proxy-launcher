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
        let b = NativeCredentialHandoff.Binding(reference:r.reference,session:.init(epoch:UUID(),generation:1,provider:"rust-xray"))
        let store=TestItems(), tickets=TestItems(), repo=NativeCredentialRepository(items:store)
        return (r,b,repo,store,tickets)
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
        let (r,b,repo,_,tickets) = try fixture(); let h=NativeCredentialHandoff(items:tickets,repository:repo,isSelected:{ $0 == r.reference })
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
        let h=NativeCredentialHandoff(items:tickets,repository:repo,isSelected:{ $0 == r.reference }), t=try h.issue(r,binding:b)
        let other=NativeCredentialHandoff.Binding(reference:r.reference,session:.init(epoch:UUID(),generation:1,provider:"rust-xray"))
        XCTAssertThrowsError(try h.redeem(t,expected:other)); XCTAssertEqual(tickets.values.count,1)
        let wrong=NativeCredentialHandoff.Binding(reference:r.reference,session:.init(epoch:b.session.epoch,generation:1,provider:"standalone-awg"))
        XCTAssertThrowsError(try h.issue(r,binding:wrong));try repo.remove(r.reference)
        XCTAssertThrowsError(try h.redeem(t,expected:b));XCTAssertTrue(tickets.values.isEmpty)
    }
    func testExpiryClockRollbackAndRevocation() throws {
        let (r,b,repo,_,tickets)=try fixture();try repo.insert(r)
        let start=Date(timeIntervalSince1970:1000);var time=start
        let h=NativeCredentialHandoff(items:tickets,repository:repo,isSelected:{ $0 == r.reference },now:{time})
        for offset in [60.0,-1.0] {
            time=start;let t=try h.issue(r,binding:b);time=start.addingTimeInterval(offset)
            XCTAssertThrowsError(try h.redeem(t,expected:b));XCTAssertTrue(tickets.values.isEmpty)
        }
        time=start;let t=try h.issue(r,binding:b);XCTAssertTrue(try h.revoke(t));XCTAssertThrowsError(try h.redeem(t,expected:b))
    }
    func testDeletionFailureNeverReturnsRecord() throws {
        let (r,b,repo,_,tickets)=try fixture();try repo.insert(r)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,isSelected:{ $0 == r.reference }),t=try h.issue(r,binding:b)
        tickets.denyRemoval=true;XCTAssertThrowsError(try h.redeem(t,expected:b));tickets.denyRemoval=false
        XCTAssertEqual(try h.redeem(t,expected:b).reference,r.reference)
    }
    func testConcurrentConsumersOnlyOneWins() throws {
        let (r,b,repo,_,tickets)=try fixture();try repo.insert(r)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,isSelected:{ $0 == r.reference }),t=try h.issue(r,binding:b)
        let winners=TestItems()
        DispatchQueue.concurrentPerform(iterations:16) { i in
            if (try? h.redeem(t,expected:b)) != nil { try? winners.insert(account:String(i),bytes:Data([1])) }
        }
        XCTAssertEqual(winners.values.count,1); XCTAssertTrue(tickets.values.isEmpty)
    }
    func testProviderReceiverConsumesExactlyOnce() throws {
        let (r,b,repo,_,tickets)=try fixture();try repo.insert(r)
        let h=NativeCredentialHandoff(items:tickets,repository:repo,isSelected:{$0 == r.reference})
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
        let h=NativeCredentialHandoff(items:tickets,repository:repo,isSelected:{$0 == r.reference})
        let t=try h.issue(r,binding:b),bytes=try TransportNativeCodec.encode(t)
        let other=NativeCredentialHandoff.Binding(reference:r.reference,session:.init(epoch:b.session.epoch,generation:2,provider:"rust-xray"))
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
        let h=NativeCredentialHandoff(items:tickets,repository:repo,isSelected:{$0 == record.reference})
        let binding=NativeCredentialHandoff.Binding(reference:record.reference,session:.init(epoch:UUID(),generation:1,provider:"rust-xray"))
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
        let h=NativeCredentialHandoff(items:tickets,repository:repo,isSelected:{_ in true}),t=try h.issue(wg,binding:b)
        let wrong=NativeCredentialHandoff.Binding(reference:v.reference,session:b.session)
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
        let h=NativeCredentialHandoff(items:tickets,repository:repo,isSelected:{ $0 == r.reference }), t=try p2.issueForValidation(local,binding:b,via:h)
        XCTAssertThrowsError(try p2.issueForValidation(local,binding:b,via:h));XCTAssertEqual(try h.redeem(t,expected:b).reference,r.reference)
    }
}
