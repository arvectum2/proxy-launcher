import Foundation
import CryptoKit
import XCTest
@testable import ArvectumProxyLauncherIOSCore

private final class CatalogMemory: NativeCredentialCatalogStorage {
    enum Failure: Error { case denied }
    var bytes: Data?, fail = false
    var failAfter: Int?
    var writes = 0
    func load() throws -> Data? { bytes }
    func replace(_ bytes: Data) throws { writes += 1; if fail || writes == failAfter { throw Failure.denied }; self.bytes = bytes }
}
private final class RecordMemory: NativeCredentialItems {
    enum Failure: Error { case denied }
    var values: [String:Data] = [:], failRemove = false
    var insertCount=0, failInsertAt: Int?
    var onInsert: (() -> Void)?
    var onRead: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    func insert(account:String,bytes:Data) throws { insertCount += 1; guard insertCount != failInsertAt, values[account] == nil else {throw Failure.denied};values[account] = bytes;onInsert?() }
    func read(account:String) throws -> Data? { onRead?(account);return values[account] }
    func remove(account:String) throws -> Bool { if failRemove {throw Failure.denied};let removed=values.removeValue(forKey:account) != nil;onRemove?(account);return removed }
}
final class NativeCredentialCatalogTests: XCTestCase {
    private func assertRestoredContent(_ actual:NativeCredentialCatalogReader.Snapshot,_ previous:NativeCredentialCatalogReader.Snapshot,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertNotNil(actual.mutationEpoch,file:file,line:line)
        XCTAssertNotEqual(actual.mutationEpoch,previous.mutationEpoch,file:file,line:line)
        var comparable=actual;comparable.mutationEpoch=previous.mutationEpoch
        XCTAssertEqual(comparable,previous,file:file,line:line)
    }
    private func record(_ id:UUID = UUID()) throws -> NativeCredentialRecord {
        let a=Curve25519.KeyAgreement.PrivateKey(),b=Curve25519.KeyAgreement.PrivateKey()
        let source="[Interface]\nPrivateKey=\(a.rawRepresentation.base64EncodedString())\nAddress=10.0.0.2/32, fd00::2/128\nDNS=192.0.2.53\n[Peer]\nPublicKey=\(b.publicKey.rawRepresentation.base64EncodedString())\nAllowedIPs=0.0.0.0/0, ::/0\nEndpoint=192.0.2.42:51820"
        return try .create(profileID:id,expected:.wireGuard,source:source)
    }
    @MainActor func testRenameMetadataPreservesSelectionAndEncryptedBackupName() throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let original=try record();try c.save(original,select:true)
        let ui=NativePersistentProfileSession(catalog:c,policy:{.tunnelOnly}),before=try c.reader.snapshot(),originalItems=items.values
        let stale=try ui.prepare(.rename(original.reference,"Old draft"))
        let rename=try ui.prepare(.rename(original.reference,"  Home tunnel  "))
        XCTAssertThrowsError(try ui.confirm(stale,vpnInactive:{true}))
        try ui.confirm(rename,vpnInactive:{true})
        let after=try c.reader.snapshot();XCTAssertEqual(after.selected,before.selected);XCTAssertEqual(after.selectionNonce,before.selectionNonce);XCTAssertEqual(items.values,originalItems)
        XCTAssertEqual(try ui.state().library.rows.first?.displayName,"Home tunnel")
        XCTAssertThrowsError(try ui.prepare(.rename(original.reference,"bad\nname")))
        let export=try ui.prepare(.exportBackup),password="Synthetic-rename-test"
        let bytes=try ui.confirmExport(export,password:password,vpnInactive:{true})
        let restored=try NativeProfileBackupCodec.open(bytes,password:password)
        XCTAssertEqual(restored.first?.displayName,"Home tunnel")
        let m2=CatalogMemory(),items2=RecordMemory(),c2=NativeCredentialCatalog(storage:m2,repository:.init(items:items2),legacyIDs:{[]})
        let added=try c2.restore(restored,vpnInactive:{true});XCTAssertEqual(added.count,1);XCTAssertNotEqual(added.first?.profileID,original.reference.profileID)
        XCTAssertEqual(try c2.reader.snapshot().displayNames?[added[0].profileID.uuidString],"Home tunnel")
        let reset=try ui.prepare(.rename(original.reference,""));try ui.confirm(reset,vpnInactive:{true});XCTAssertNil(try ui.state().library.rows.first?.displayName)
        XCTAssertEqual(items.values,originalItems)
    }
    @MainActor func testReplacementKeepsIdentityAndRollsBackBeforePublication() throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let original=try record(),other=try record();try c.save(original,select:true);try c.save(other,select:false)
        let ui=NativePersistentProfileSession(catalog:c,policy:{.tunnelOnly})
        try ui.confirm(ui.prepare(.rename(original.reference,"Home")),vpnInactive:{true})
        let before=try c.reader.snapshot(),oldItems=items.values,new=automaticSources()
        XCTAssertThrowsError(try ui.previewReplacement(new.vless,for:original.reference))
        let stale=try ui.previewReplacement(new.wg,for:original.reference)
        _=try ui.prepare(.rename(other.reference,"Other"));XCTAssertThrowsError(try ui.confirm(stale,vpnInactive:{true}))
        let denied=try ui.previewReplacement(new.wg,for:original.reference);XCTAssertThrowsError(try ui.confirm(denied,vpnInactive:{false}));XCTAssertEqual(try c.reader.snapshot(),before)
        let rollback=try ui.previewReplacement(new.wg,for:original.reference);m.failAfter=m.writes+2
        XCTAssertThrowsError(try ui.confirm(rollback,vpnInactive:{true}));assertRestoredContent(try c.reader.snapshot(),before);XCTAssertEqual(items.values,oldItems)
        m.failAfter=nil
        let success=try ui.previewReplacement(new.wg,for:original.reference);try ui.confirm(success,vpnInactive:{true})
        let after=try c.reader.snapshot(),ref=try XCTUnwrap(after.current.first)
        XCTAssertEqual(ref.profileID,original.reference.profileID);XCTAssertNotEqual(ref.revision,original.reference.revision);XCTAssertEqual(ref.kind,original.reference.kind)
        XCTAssertEqual(after.current,[ref,other.reference]);XCTAssertEqual(after.retired,[original.reference]);XCTAssertNil(after.selected);XCTAssertNil(after.selectionNonce)
        XCTAssertEqual(after.displayNames?[ref.profileID.uuidString],"Home");XCTAssertEqual(items.values.count,3)
        XCTAssertThrowsError(try ui.confirm(success,vpnInactive:{true}))
        let select=try ui.prepare(.select(ref));try ui.confirm(select,vpnInactive:{true});XCTAssertEqual(try c.reader.snapshot().selected,ref)
        XCTAssertNotEqual(try c.reader.snapshot().selectionNonce,before.selectionNonce)
    }
    @MainActor func testEndpointEditorPreservesEngineParametersAndRejectsStaleDraft() throws {
        let sources=automaticSources(),m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let ui=NativePersistentProfileSession(catalog:c,policy:{.tunnelOnly})
        for (protocolKind,source) in [(TransportProtocol.wireGuard,sources.wg),(.amneziaWG1,sources.awg),(.vlessReality,sources.vless)] {
            let old=try NativeCredentialRecord.create(profileID:UUID(),expected:protocolKind,source:source);try c.save(old,select:true)
            let before=try c.reader.snapshot(),originalItems=items.values
            XCTAssertThrowsError(try ui.beginEndpointEdit(old.reference,vpnInactive:{false}))
            for host in ["example.com","127.0.0.1","192.0.2.53","192.0.2.43\nEndpoint=192.0.2.42:123"] {
                // VLESS has no tunnel DNS configuration; its literal unicast DNS address is allowed.
                if protocolKind == .vlessReality && host == "192.0.2.53" {continue}
                let draft=try ui.beginEndpointEdit(old.reference,vpnInactive:{true})
                XCTAssertThrowsError(try ui.previewEndpointEdit(draft,host:host,port:4444,vpnInactive:{true}))
            }
            let draft=try ui.beginEndpointEdit(old.reference,vpnInactive:{true});_ = try ui.prepare(.rename(old.reference,"Stale"))
            XCTAssertThrowsError(try ui.previewEndpointEdit(draft,host:"192.0.2.43",port:4444,vpnInactive:{true}))
            XCTAssertEqual(items.values,originalItems);XCTAssertEqual(try c.reader.snapshot(),before)
            let good=try ui.beginEndpointEdit(old.reference,vpnInactive:{true})
            let receipt=try ui.previewEndpointEdit(good,host:"192.0.2.43",port:4444,vpnInactive:{true})
            XCTAssertEqual(receipt.endpoint?.address,"192.0.2.43:4444");XCTAssertEqual(items.values,originalItems)
            try ui.confirm(receipt,vpnInactive:{true})
            let ref=try XCTUnwrap(c.reader.snapshot().current.first{$0.profileID==old.reference.profileID}),new=try XCTUnwrap(repo.read(ref))
            XCTAssertNotEqual(ref.revision,old.reference.revision);XCTAssertNil(try c.reader.snapshot().selected)
            let oldBytes=try old.compile().0.withEngineConfiguration{$0},newBytes=try new.compile().0.withEngineConfiguration{$0}
            if protocolKind == .vlessReality {
                var expected=try XCTUnwrap(JSONSerialization.jsonObject(with:oldBytes) as? [String:Any])
                var out=try XCTUnwrap(expected["outbounds"] as? [[String:Any]])
                var settings=try XCTUnwrap(out[0]["settings"] as? [String:Any]);settings["address"]="192.0.2.43";settings["port"]=4444;out[0]["settings"]=settings;expected["outbounds"]=out
                XCTAssertEqual(try JSONSerialization.data(withJSONObject:expected,options:[.sortedKeys]),newBytes)
            } else {
                let expected=String(decoding:oldBytes,as:UTF8.self).replacingOccurrences(of:good.endpoint.address,with:"192.0.2.43:4444")
                XCTAssertEqual(Data(expected.utf8),newBytes)
                let ipv6=try new.replacingEndpoint(host:"2001:db8::42",port:51820);XCTAssertEqual(try ipv6.endpointForEdit().address,"[2001:db8::42]:51820")
            }
            XCTAssertThrowsError(try ui.confirm(receipt,vpnInactive:{true}))
        }
    }
    @MainActor func testUnifiedImportClassifiesAndTransfersOnlyOnce() throws {
        let a=automaticSources(),b=automaticSources()
        let legacy="http://user:pass@192.0.2.42:8080\n192.0.2.43:1080"
        guard case .proxy(let rows)=try UnifiedProfileImport.parse(legacy,defaultType:.socks5) else{return XCTFail("Wrong family")}
        XCTAssertEqual(rows,try ProxyImport.parse(legacy,defaultType:.socks5))
        for (source,kind) in [("\u{FEFF}# comment\n"+a.wg,NativeCredentialRecord.Kind.wireGuard),(a.awg,.amneziaWG1),(a.vless+"\n"+b.vless,.vlessReality)] {
            guard case .native(let records)=try UnifiedProfileImport.parse(source,defaultType:.http) else{return XCTFail("Wrong family")}
            XCTAssertTrue(records.allSatisfy{$0.reference.kind==kind})
            let target=NativeProfileReviewSession(),transfer=NativeImportTransfer(records)
            let summary=try target.previewTransfer(transfer);XCTAssertEqual(summary.count,records.count);XCTAssertEqual(try target.counts().total,0)
            XCTAssertThrowsError(try transfer.take())
            _=try target.addToRehearsal(summary);XCTAssertEqual(try target.counts().total,records.count)
            let discarded=NativeImportTransfer(records);discarded.discard();XCTAssertThrowsError(try target.previewTransfer(discarded))
        }
        for source in [legacy+"\n"+a.vless,a.vless+"\n"+legacy,a.wg+"\n"+legacy,"[Peer]\nEndpoint=192.0.2.42:51820",a.awg.replacingOccurrences(of:"H4=32345\n",with:"")] {
            XCTAssertThrowsError(try UnifiedProfileImport.parse(source,defaultType:.http))
        }
    }
    private func automaticSources() -> (wg:String,awg:String,vless:String) {
        let a=Curve25519.KeyAgreement.PrivateKey(),b=Curve25519.KeyAgreement.PrivateKey()
        let wg="[Interface]\nPrivateKey=\(a.rawRepresentation.base64EncodedString())\nAddress=10.0.0.2/32, fd00::2/128\nDNS=192.0.2.53\n[Peer]\nPublicKey=\(b.publicKey.rawRepresentation.base64EncodedString())\nAllowedIPs=0.0.0.0/0, ::/0\nEndpoint=192.0.2.42:51820"
        let awg=wg.replacingOccurrences(of:"[Peer]",with:"Jc=0\nJmin=0\nJmax=0\nS1=15\nS2=18\nH1=123456\nH2=67543\nH3=123123\nH4=32345\n[Peer]")
        let key=b.publicKey.rawRepresentation.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        let vless="vless://\(UUID().uuidString.lowercased())@192.0.2.42:443?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk=\(key)&sid=abcd"
        return (wg,awg,vless)
    }
    func testAutomaticImportIdentifiesStrictProtocolsAndRejectsMixedInvalidInput() throws {
        let a=automaticSources(),b=automaticSources()
        let records=try NativeAutomaticImport.prepare(["# comment\n"+a.wg,a.awg," "+a.vless+"\r\n\n"+b.vless])
        XCTAssertEqual(records.map(\.reference.kind),[.wireGuard,.amneziaWG1,.vlessReality,.vlessReality])
        XCTAssertEqual(Set(records.map(\.reference.profileID)).count,4)
        for raw in [a.awg.replacingOccurrences(of:"H4=32345\n",with:""),a.awg.replacingOccurrences(of:"H4=32345",with:"H4=32345\nI1=123"),a.wg+"\n"+b.wg,a.vless+"\nhttps://example.com",a.vless+"\n"+a.wg,"https://example.com"," ",a.wg.replacingOccurrences(of:"0.0.0.0/0, ::/0",with:"10.0.0.0/8")] {
            XCTAssertThrowsError(try NativeAutomaticImport.prepare([a.vless,raw]))
        }
        XCTAssertThrowsError(try NativeAutomaticImport.prepare([a.wg," \n"+a.wg+"\n"])) {XCTAssertEqual($0 as? NativeAutomaticImport.Failure,.duplicate)}
        XCTAssertThrowsError(try NativeAutomaticImport.prepare([String(repeating:"x",count:NativeAutomaticImport.maxBytes+1)])) {XCTAssertEqual($0 as? NativeAutomaticImport.Failure,.tooLarge)}
        XCTAssertThrowsError(try NativeAutomaticImport.prepare(Array(repeating:a.vless,count:33))) {XCTAssertEqual($0 as? NativeAutomaticImport.Failure,.tooLarge)}
        let links=(0..<33).map{_ in automaticSources().vless}.joined(separator:"\n")
        XCTAssertThrowsError(try NativeAutomaticImport.prepare([links])) {XCTAssertEqual($0 as? NativeAutomaticImport.Failure,.tooLarge)}
    }
    @MainActor func testAutomaticBatchPreviewAtomicConfirmationAndStaleReview() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let original=try record();try c.save(original,select:true)
        let ui=NativePersistentProfileSession(catalog:c,policy:{.tunnelOnly}),a=automaticSources()
        let before=try c.reader.snapshot(),writes=m.writes
        let stale=try ui.previewAutomatic([a.wg,a.awg,a.vless]);XCTAssertEqual(stale.count,3);XCTAssertEqual(stale.existingCount,1)
        XCTAssertEqual(m.writes,writes);XCTAssertEqual(items.values.count,1)
        XCTAssertThrowsError(try ui.previewAutomatic([a.wg,"not a configuration"]))
        XCTAssertThrowsError(try ui.confirmImport(stale,vpnInactive:{true}))
        let denied=try ui.previewAutomatic([a.wg,a.awg,a.vless]);XCTAssertThrowsError(try ui.confirmImport(denied,vpnInactive:{false}))
        XCTAssertEqual(try c.reader.snapshot(),before)
        let reviewed=try ui.previewAutomatic([a.wg,a.awg,a.vless]);items.failInsertAt=items.insertCount+2
        XCTAssertThrowsError(try ui.confirmImport(reviewed,vpnInactive:{true}));XCTAssertEqual(items.values.count,1)
        assertRestoredContent(try c.reader.snapshot(),before)
        items.failInsertAt=nil
        let final=try ui.previewAutomatic([a.wg,a.awg,a.vless]);try ui.confirmImport(final,vpnInactive:{true})
        let after=try c.reader.snapshot();XCTAssertEqual(after.selected,before.selected);XCTAssertEqual(after.selectionNonce,before.selectionNonce);XCTAssertEqual(after.current.count,4);XCTAssertEqual(items.values.count,4)
        XCTAssertThrowsError(try ui.confirmImport(final,vpnInactive:{true}))
    }
    @MainActor func testIPRoutePreviewReadsOnlySelectedRevisionWithoutMutation() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record(),b=try record();try c.save(a,select:true);try c.save(b,select:false)
        var admission=NativeRoutingAdmission.tunnelOnly,reads=0
        let ui=NativePersistentProfileSession(catalog:c,policy:{admission});items.onRead={_ in reads+=1}
        let before=try c.reader.snapshot(),writes=m.writes
        for ref in [a.reference,b.reference] {
            XCTAssertThrowsError(try ui.previewIPRoutes(for:ref,explicitRules:["example.com"],explicitIPOptIn:true,vpnInactive:{true}))
            XCTAssertThrowsError(try ui.previewIPRoutes(for:ref,explicitRules:["198.51.100.7"],explicitIPOptIn:false,vpnInactive:{true}))
        }
        XCTAssertThrowsError(try ui.previewIPRoutes(for:b.reference,explicitRules:["198.51.100.7"],explicitIPOptIn:true,vpnInactive:{true}))
        XCTAssertThrowsError(try ui.previewIPRoutes(for:a.reference,explicitRules:["198.51.100.7"],explicitIPOptIn:true,vpnInactive:{false}))
        XCTAssertEqual(reads,0)
        let plan=try ui.previewIPRoutes(for:a.reference,explicitRules:["198.51.100.7","2001:db8:99::/48"],explicitIPOptIn:true,vpnInactive:{true})
        XCTAssertEqual(plan.exclusions.map(\.description),["198.51.100.7/32","2001:db8:99::/48"]);XCTAssertEqual(reads,1)
        XCTAssertEqual(try c.reader.snapshot(),before);XCTAssertEqual(m.writes,writes)
        XCTAssertThrowsError(try ui.previewIPRoutes(for:a.reference,explicitRules:["192.0.2.53"],explicitIPOptIn:true,vpnInactive:{true}))
        items.onRead={_ in admission = .siteExclusions}
        XCTAssertThrowsError(try ui.previewIPRoutes(for:a.reference,explicitRules:["198.51.100.7"],explicitIPOptIn:true,vpnInactive:{true}))
        admission = .tunnelOnly;items.onRead={_ in var changed=before;changed.mutationEpoch=UUID();m.bytes=try? JSONEncoder().encode(changed)}
        XCTAssertThrowsError(try ui.previewIPRoutes(for:a.reference,explicitRules:["198.51.100.7"],explicitIPOptIn:true,vpnInactive:{true}))
        XCTAssertEqual(m.writes,writes);XCTAssertEqual(items.values.count,2)
    }
    @MainActor func testMutationEpochInvalidatesRestoredContentAndBackupReceipts() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record();try c.save(a,select:true)
        // Read v2 without epoch, then ensure the next journal publishes one.
        var original=try c.reader.snapshot();original.mutationEpoch=nil;m.bytes=try JSONEncoder().encode(original)
        let ui=NativePersistentProfileSession(catalog:c,policy:{.tunnelOnly})
        let old=try ui.prepare(.exportBackup)
        let other=try record();try c.save(other,select:false);try c.remove(other.reference);try c.reconcileRetired()
        assertRestoredContent(try c.reader.snapshot(),original)
        XCTAssertThrowsError(try ui.confirmExport(old,password:"test-backup-1234",vpnInactive:{true}))
        let review=try ui.prepare(.remove(a.reference));let before=try c.reader.snapshot()
        items.failInsertAt=items.insertCount+1
        XCTAssertThrowsError(try c.restore([try record()],vpnInactive:{true}))
        assertRestoredContent(try c.reader.snapshot(),before)
        XCTAssertThrowsError(try ui.confirm(review,vpnInactive:{true}))
        XCTAssertNotNil(try repo.read(a.reference))
        let unchanged=try c.reader.snapshot();m.fail=true
        XCTAssertThrowsError(try c.select(a.reference));XCTAssertEqual(try c.reader.snapshot(),unchanged)
    }
    @MainActor func testPersistentEncryptedExportAndAdditiveBackupImport() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record(),retired=try record();try c.save(a,select:true);try c.save(retired,select:false);try c.remove(retired.reference)
        let ui=NativePersistentProfileSession(catalog:c,policy:{.tunnelOnly}),password="test-backup-1234"
        let inactive=try ui.prepare(.exportBackup);XCTAssertThrowsError(try ui.confirmExport(inactive,password:password,vpnInactive:{false}))
        let before=try c.reader.snapshot(),receipt=try ui.prepare(.exportBackup)
        let encrypted=try ui.confirmExport(receipt,password:password,vpnInactive:{true})
        XCTAssertEqual(try c.reader.snapshot(),before);XCTAssertEqual(try NativeProfileBackupCodec.open(encrypted,password:password).map(\.reference),[a.reference])
        XCTAssertThrowsError(try ui.confirmExport(receipt,password:password,vpnInactive:{true}))
        XCTAssertThrowsError(try ui.previewBackup(encrypted,password:"wrong-password"))
        let preview=try ui.previewBackup(encrypted,password:password);XCTAssertEqual(preview.count,1);XCTAssertEqual(items.values.count,2)
        try ui.confirmImport(preview,vpnInactive:{true});XCTAssertEqual(try c.reader.snapshot().current.count,2);XCTAssertTrue(try c.reader.isSelected(a.reference));XCTAssertEqual(try c.reader.snapshot().retired,[retired.reference]);XCTAssertEqual(items.values.count,3)
        XCTAssertThrowsError(try ui.confirmImport(preview,vpnInactive:{true}))
    }
    @MainActor func testPersistentLibraryExplicitSelectionAndRemovalCleanup() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record(),b=try record();try c.save(a,select:true);try c.save(b,select:false)
        var policy=NativeRoutingAdmission.tunnelOnly
        let s=NativePersistentProfileSession(catalog:c,policy:{policy})
        let select=try s.prepare(.select(b.reference));policy = .siteExclusions
        XCTAssertThrowsError(try s.confirm(select,vpnInactive:{true}));XCTAssertTrue(try c.reader.isSelected(a.reference));XCTAssertFalse(try s.state().policyAllowsSelection)
        policy = .tunnelOnly;let next=try s.prepare(.select(b.reference));try s.confirm(next,vpnInactive:{true});XCTAssertTrue(try c.reader.isSelected(b.reference))
        XCTAssertThrowsError(try s.confirm(next,vpnInactive:{true}))
        let deletion=try s.prepare(.remove(b.reference));XCTAssertThrowsError(try s.confirm(deletion,vpnInactive:{false}));XCTAssertNotNil(try repo.read(b.reference))
        let again=try s.prepare(.remove(b.reference));try s.confirm(again,vpnInactive:{true})
        XCTAssertEqual(try s.state().retiredCount,1);XCTAssertNotNil(try repo.read(b.reference));XCTAssertNil(try c.reader.snapshot().selected)
        let purge=try s.prepare(.purgeRetired);var active=true;items.onRemove={_ in active=false}
        XCTAssertThrowsError(try s.confirm(purge,vpnInactive:{active}));XCTAssertEqual(try s.state().retiredCount,1);XCTAssertNotNil(try repo.read(a.reference))
        items.onRemove=nil;let retry=try s.prepare(.purgeRetired);try s.confirm(retry,vpnInactive:{true});XCTAssertEqual(try s.state().retiredCount,0);XCTAssertNil(try repo.read(b.reference));XCTAssertNotNil(try repo.read(a.reference))
    }
    @MainActor func testPersistentLibraryMigrationAndEmptyPendingRecovery() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record();try c.save(a,select:true);var legacy=try c.reader.snapshot();legacy.version=1;m.bytes=try JSONEncoder().encode(legacy)
        var clock=10.0;let s=NativePersistentProfileSession(catalog:c,policy:{.tunnelOnly},elapsed:{clock})
        XCTAssertTrue(try s.state().migrationRequired);let first=try s.prepare(.migrate);clock+=300
        XCTAssertThrowsError(try s.confirm(first,vpnInactive:{true}));let migrate=try s.prepare(.migrate);try s.confirm(migrate,vpnInactive:{true})
        XCTAssertTrue(try s.state().selectionNeedsReview);XCTAssertNil(try c.reader.selectionAuthority(a.reference))
        let tmp=try record();try repo.insert(tmp);var pending=try c.reader.snapshot();pending.pendingInsert=tmp.reference;m.bytes=try JSONEncoder().encode(pending)
        XCTAssertTrue(try s.state().recoveryRequired);let recover=try s.prepare(.recover);s.cancel();XCTAssertThrowsError(try s.confirm(recover,vpnInactive:{true}));XCTAssertNotNil(try repo.read(tmp.reference))
        let retry=try s.prepare(.recover);try s.confirm(retry,vpnInactive:{true});XCTAssertFalse(try s.state().recoveryRequired);XCTAssertNil(try repo.read(tmp.reference));XCTAssertNotNil(try repo.read(a.reference))
    }
    @MainActor func testPersistentLibraryImportDoesNotSelectAndStaleReceiptFails() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record();try c.save(a,select:true)
        let s=NativePersistentProfileSession(catalog:c,policy:{.tunnelOnly})
        let old=try s.prepare(.remove(a.reference));try c.save(try record(),select:false);XCTAssertThrowsError(try s.confirm(old,vpnInactive:{true}))
        let key=Curve25519.KeyAgreement.PrivateKey(),peer=Curve25519.KeyAgreement.PrivateKey()
        let source="[Interface]\nPrivateKey=\(key.rawRepresentation.base64EncodedString())\nAddress=10.0.0.2/32, fd00::2/128\nDNS=192.0.2.53\n[Peer]\nPublicKey=\(peer.publicKey.rawRepresentation.base64EncodedString())\nAllowedIPs=0.0.0.0/0, ::/0\nEndpoint=192.0.2.42:51820"
        let preview=try s.previewSource(source,kind:.wireGuard);XCTAssertEqual(items.values.count,2);try s.confirmImport(preview,vpnInactive:{true});XCTAssertEqual(items.values.count,3);XCTAssertTrue(try c.reader.isSelected(a.reference))
        XCTAssertThrowsError(try s.confirmImport(preview,vpnInactive:{true}))
    }
    @MainActor func testReplacementRejectsAlreadyIssuedTicketBeforeCleanup() async throws {
        let m=CatalogMemory(), items=RecordMemory(), tickets=RecordMemory(), repo=NativeCredentialRepository(items:items)
        let c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let first=try record();try c.save(first,select:true)
        let reader=c.reader, h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{try reader.authorizes($0)})
        let binding=NativeCredentialHandoff.Binding(reference:first.reference,session:.init(epoch:UUID(),generation:1,provider:"rust-xray"),selectionNonce:try XCTUnwrap(reader.selectionAuthority(first.reference)))
        let ticket=try h.issue(first,binding:binding)
        let second=try record(first.reference.profileID);try c.save(second,select:true)
        XCTAssertNotNil(try repo.read(first.reference));XCTAssertThrowsError(try h.redeem(ticket,expected:binding))
        XCTAssertTrue(try reader.isSelected(second.reference));XCTAssertEqual(try reader.snapshot().retired,[first.reference])
        try c.reconcileRetired();XCTAssertNil(try repo.read(first.reference));XCTAssertNotNil(try repo.read(second.reference))
    }
    @MainActor func testSelectionSwitchBackCannotReviveIssuedTicket() async throws {
        let m=CatalogMemory(),items=RecordMemory(),tickets=RecordMemory(),repo=NativeCredentialRepository(items:items)
        let c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record(),b=try record();try c.save(a,select:true);try c.save(b,select:false)
        let reader=c.reader,session=TransportNativeIdentity(epoch:UUID(),generation:1,provider:"rust-xray")
        let h=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{try reader.authorizes($0)})
        let old=NativeCredentialHandoff.Binding(reference:a.reference,session:session,selectionNonce:try XCTUnwrap(reader.selectionAuthority(a.reference)))
        let ticket=try h.issue(a,binding:old)
        try c.select(b.reference);try c.select(a.reference)
        XCTAssertTrue(try reader.isSelected(a.reference));XCTAssertFalse(try reader.authorizes(old))
        XCTAssertThrowsError(try h.redeem(ticket,expected:old));XCTAssertThrowsError(try h.issue(a,binding:old))
        let fresh=NativeCredentialHandoff.Binding(reference:a.reference,session:session,selectionNonce:try XCTUnwrap(reader.selectionAuthority(a.reference)))
        XCTAssertNotEqual(fresh.selectionNonce,old.selectionNonce)
        let next=try h.issue(a,binding:fresh);XCTAssertEqual(try h.redeem(next,expected:fresh).reference,a.reference)
        try c.select(a.reference);XCTAssertFalse(try reader.authorizes(fresh))
    }
    @MainActor func testLegacySelectionHasNoHandoffAuthorityUntilExplicitSelection() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record();try c.save(a,select:true)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(m.bytes)) as? [String:Any]);json["version"]=1;json.removeValue(forKey:"selectionNonce");m.bytes=try JSONSerialization.data(withJSONObject:json)
        XCTAssertTrue(try c.reader.isSelected(a.reference));XCTAssertNil(try c.reader.selectionAuthority(a.reference))
        XCTAssertThrowsError(try c.select(a.reference));try c.migrateLegacyForValidation(vpnInactive:{true})
        try c.select(a.reference);XCTAssertNotNil(try c.reader.selectionAuthority(a.reference))
        try c.remove(a.reference);XCTAssertNil(try c.reader.snapshot().selectionNonce)
    }
    @MainActor func testRestorePreviewInvalidatedBySelectionRoundTrip() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record(),b=try record();try c.save(a,select:true);try c.save(b,select:false)
        let password="Synthetic-passphrase-2026",bytes=try NativeProfileBackupCodec.seal([try record()],password:password),review=NativeRestoreReview(catalog:c)
        let s=try review.preview(data:bytes,password:password);try c.select(b.reference);try c.select(a.reference)
        XCTAssertThrowsError(try review.confirm(s,vpnInactive:{true}));XCTAssertEqual(try c.reader.snapshot().current.count,2)
    }
    @MainActor func testPendingInsertDeniesAuthorityAndRecoveryKeepsOriginalSelection() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record();try c.save(a,select:true);let token=try XCTUnwrap(c.reader.selectionAuthority(a.reference))
        m.failAfter=m.writes+2;items.failRemove=true
        XCTAssertThrowsError(try c.save(try record(),select:false));XCTAssertNil(try c.reader.selectionAuthority(a.reference))
        items.failRemove=false;try c.reconcilePendingInsert();XCTAssertEqual(try c.reader.selectionAuthority(a.reference),token)
    }
    @MainActor func testProtocolReplacementWithinSameProviderRetiresOldRevision() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let first=try record();try c.save(first,select:true)
        let key=Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        let vless=try NativeCredentialRecord.create(profileID:first.reference.profileID,expected:.vlessReality,source:"vless://\(UUID().uuidString.lowercased())@192.0.2.42:443?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk=\(key)&sid=abcd")
        try c.save(vless,select:true)
        XCTAssertTrue(try c.reader.isSelected(vless.reference));XCTAssertFalse(try c.reader.isSelected(first.reference))
        try c.reconcileRetired();XCTAssertNil(try repo.read(first.reference));XCTAssertEqual(try repo.read(vless.reference)?.reference.kind,.vlessReality)
    }
    @MainActor func testBackupSnapshotsOnlyCurrentRecordsAndRejectsMissing() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let first=try record();try c.save(first,select:true)
        let second=try record(first.reference.profileID);try c.save(second,select:false)
        XCTAssertEqual(try c.reader.currentRecordsForBackup(repository:repo).map(\.reference),[second.reference])
        XCTAssertNotNil(try repo.read(first.reference));try repo.remove(second.reference)
        XCTAssertThrowsError(try c.reader.currentRecordsForBackup(repository:repo))
    }
    @MainActor func testFailedPublishRollsBackNewRecord() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let first=try record();try c.save(first,select:true);let second=try record(first.reference.profileID)
        m.fail=true;XCTAssertThrowsError(try c.save(second,select:true));XCTAssertNil(try repo.read(second.reference));XCTAssertTrue(try c.reader.isSelected(first.reference));XCTAssertEqual(items.values.count,1)
    }
    @MainActor func testRetirementSurvivesCleanupAndPublicationFailure() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let first=try record();try c.save(first,select:true);try c.remove(first.reference)
        XCTAssertFalse(try c.reader.isSelected(first.reference));items.failRemove=true;XCTAssertThrowsError(try c.reconcileRetired());items.failRemove=false
        m.fail=true;XCTAssertThrowsError(try c.reconcileRetired());XCTAssertNil(try repo.read(first.reference));XCTAssertEqual(try c.reader.snapshot().retired.count,1)
        m.fail=false;try c.reconcileRetired();XCTAssertTrue(try c.reader.snapshot().retired.isEmpty)
    }
    @MainActor func testInterruptedCommitReconcilesExactPendingRecord() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let first=try record();try c.save(first,select:true);let second=try record(first.reference.profileID)
        // Simulate failure of final commit AND cleanup, after journal persisted.
        m.failAfter=m.writes+2;items.failRemove=true
        XCTAssertThrowsError(try c.save(second,select:true));XCTAssertNotNil(try repo.read(second.reference));XCTAssertTrue(try c.reader.isSelected(first.reference))
        XCTAssertEqual(try c.reader.snapshot().pendingInsert,second.reference)
        XCTAssertThrowsError(try c.save(try record(),select:true))
        items.failRemove=false;try c.reconcilePendingInsert()
        XCTAssertNil(try repo.read(second.reference));XCTAssertNil(try c.reader.snapshot().pendingInsert);XCTAssertTrue(try c.reader.isSelected(first.reference))
    }
    @MainActor func testBatchRestorePublishesFreshRecordsAndKeepsSelection() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items)
        let first=try record(), c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        try c.save(first,select:true)
        let incoming=[try record(first.reference.profileID),try record()]
        var sawPending=false
        items.onInsert={
            let snapshot=try! c.reader.snapshot()
            XCTAssertEqual(snapshot.current,[first.reference]);XCTAssertNotNil(snapshot.pendingRestore)
            XCTAssertFalse(try! c.reader.isSelected(first.reference));sawPending=true
        }
        let restored=try c.restore(incoming,vpnInactive:{true});items.onInsert=nil
        XCTAssertTrue(sawPending);XCTAssertEqual(restored.count,2)
        XCTAssertEqual(try c.reader.snapshot().current,[first.reference]+restored)
        XCTAssertTrue(try c.reader.isSelected(first.reference));XCTAssertNil(try c.reader.snapshot().pendingRestore)
        XCTAssertTrue(Set(restored.map(\.profileID)).isDisjoint(with:Set(incoming.map(\.reference.profileID))))
        XCTAssertEqual(items.values.count,3)
    }
    @MainActor func testBatchRestoreRejectsActiveVPNAndRollsBackPartialInsert() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let first=try record();try c.save(first,select:true)
        let before=try c.reader.snapshot(),incoming=[try record(),try record()]
        XCTAssertThrowsError(try c.restore(incoming,vpnInactive:{false}));XCTAssertEqual(items.values.count,1)
        items.failInsertAt=items.insertCount+2
        XCTAssertThrowsError(try c.restore(incoming,vpnInactive:{true}));assertRestoredContent(try c.reader.snapshot(),before);XCTAssertEqual(items.values.count,1)
    }
    @MainActor func testBatchJournalSurvivesCrashBeforeCommitAndCleanup() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let first=try record();try c.save(first,select:true)
        let before=try c.reader.snapshot()
        m.failAfter=m.writes+2;items.failRemove=true
        XCTAssertThrowsError(try c.restore([try record(),try record()],vpnInactive:{true}))
        let pending=try c.reader.snapshot();XCTAssertEqual(pending.current,before.current);XCTAssertEqual(pending.pendingRestore?.count,2);XCTAssertEqual(items.values.count,3)
        XCTAssertThrowsError(try c.save(try record(),select:true));XCTAssertThrowsError(try c.select(first.reference));XCTAssertThrowsError(try c.reader.currentRecordsForBackup(repository:repo))
        items.failRemove=false
        XCTAssertThrowsError(try c.reconcilePendingRestore(vpnInactive:{false}))
        try c.reconcilePendingRestore(vpnInactive:{true});try c.reconcilePendingRestore(vpnInactive:{true})
        assertRestoredContent(try c.reader.snapshot(),before);XCTAssertEqual(items.values.count,1)
    }
    @MainActor func testBatchVPNBecomesActiveDuringInsertDefersRecovery() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        var inactive=true;items.onInsert={inactive=false}
        XCTAssertThrowsError(try c.restore([try record(),try record()],vpnInactive:{inactive}));XCTAssertEqual(items.values.count,1)
        XCTAssertEqual(try c.reader.snapshot().current,[]);XCTAssertEqual(try c.reader.snapshot().pendingRestore?.count,2)
        inactive=true;try c.reconcilePendingRestore(vpnInactive:{inactive});assertRestoredContent(try c.reader.snapshot(),.empty);XCTAssertTrue(items.values.isEmpty)
    }
    @MainActor func testLegacySnapshotDecodesAndFailedJournalClearIsRetryable() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let original=try record();try c.save(original,select:true)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(m.bytes)) as? [String:Any]);json["version"]=1;json.removeValue(forKey:"pendingRestore")
        m.bytes=try JSONSerialization.data(withJSONObject:json);try c.migrateLegacyForValidation(vpnInactive:{true});let old=try c.reader.snapshot()
        XCTAssertNil(old.pendingRestore);XCTAssertTrue(try c.reader.isSelected(original.reference))
        m.failAfter=m.writes+2;items.failRemove=true
        XCTAssertThrowsError(try c.restore([try record(),try record()],vpnInactive:{true}))
        items.failRemove=false;m.fail=true
        XCTAssertThrowsError(try c.reconcilePendingRestore(vpnInactive:{true}));XCTAssertEqual(items.values.count,1)
        XCTAssertNotNil(try c.reader.snapshot().pendingRestore)
        m.fail=false;try c.reconcilePendingRestore(vpnInactive:{true});assertRestoredContent(try c.reader.snapshot(),old)
    }
    @MainActor func testRestoreReviewRequiresCurrentSingleUseConfirmation() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items)
        let c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let r=try record(),password="Synthetic-passphrase-2026",bytes=try NativeProfileBackupCodec.seal([r],password:password)
        let review=NativeRestoreReview(catalog:c)
        let summary=try review.preview(data:bytes,password:password)
        XCTAssertEqual(summary.count,1);XCTAssertEqual(summary.wireGuard,1);XCTAssertEqual(summary.existingCount,0);XCTAssertTrue(items.values.isEmpty)
        let refs=try review.confirm(summary,vpnInactive:{true})
        XCTAssertEqual(refs.count,1);XCTAssertNotEqual(refs[0].profileID,r.reference.profileID)
        XCTAssertThrowsError(try review.confirm(summary,vpnInactive:{true}));XCTAssertEqual(items.values.count,1)
    }
    @MainActor func testRestoreReviewRejectsChangedCatalogAndLegacyIDs() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items)
        var legacy=Set<UUID>();let c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{legacy})
        let password="Synthetic-passphrase-2026",bytes=try NativeProfileBackupCodec.seal([try record()],password:password),review=NativeRestoreReview(catalog:c)
        let first=try review.preview(data:bytes,password:password);try c.save(try record(),select:true)
        XCTAssertThrowsError(try review.confirm(first,vpnInactive:{true}))
        let second=try review.preview(data:bytes,password:password);legacy.insert(UUID())
        XCTAssertThrowsError(try review.confirm(second,vpnInactive:{true}));XCTAssertEqual(items.values.count,1)
    }
    @MainActor func testRestoreReviewExpiresCancelsAndFailedPreviewClears() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        var clock=100.0;let review=NativeRestoreReview(catalog:c,elapsed:{clock})
        let password="Synthetic-passphrase-2026",bytes=try NativeProfileBackupCodec.seal([try record()],password:password)
        let old=try review.preview(data:bytes,password:password);clock+=300
        XCTAssertThrowsError(try review.confirm(old,vpnInactive:{true}))
        let dismissed=try review.preview(data:bytes,password:password);review.cancel();XCTAssertThrowsError(try review.confirm(dismissed,vpnInactive:{true}))
        let prior=try review.preview(data:bytes,password:password);XCTAssertThrowsError(try review.preview(data:bytes,password:"Wrong-passphrase-2026"));XCTAssertThrowsError(try review.confirm(prior,vpnInactive:{true}))
        let active=try review.preview(data:bytes,password:password);XCTAssertThrowsError(try review.confirm(active,vpnInactive:{false}));XCTAssertThrowsError(try review.confirm(active,vpnInactive:{true}))
        XCTAssertTrue(items.values.isEmpty)
    }
    @MainActor func testGateRejectsNestedAndConcurrentOperationsAcrossSuspension() async throws {
        let gate=NativeOperationGate()
        try await gate.perform(.start) {
            XCTAssertEqual(gate.active,.start)
            do {try await gate.perform(.restore) { XCTFail("nested") };XCTFail("not rejected")} catch {}
            await Task.yield()
            XCTAssertEqual(gate.active,.start)
        }
        XCTAssertNil(gate.active)
        enum Probe:Error {case failure}
        do {try await gate.perform(.restore){throw Probe.failure};XCTFail("expected failure")} catch {}
        XCTAssertNil(gate.active)
        var ran=false;try await gate.perform(.start){ran=true};XCTAssertTrue(ran)
    }
    @MainActor func testGateRejectsIndependentTaskWhileStartIsSuspended() async throws {
        let gate=NativeOperationGate()
        var resume: CheckedContinuation<Void,Never>?
        let start=Task { @MainActor in
            try await gate.perform(.start) {
                await withCheckedContinuation{(c:CheckedContinuation<Void,Never>) in resume=c}
                try Task.checkCancellation()
            }
        }
        while resume == nil {await Task.yield()}
        do {try await gate.perform(.restore){XCTFail("concurrent restore")};XCTFail("expected busy")} catch {}
        start.cancel();resume?.resume()
        do {try await start.value;XCTFail("expected cancelled")} catch {}
        XCTAssertNil(gate.active)
        try await gate.perform(.restore){XCTAssertEqual(gate.active,.restore)}
    }
    @MainActor func testInvalidRestoreJournalCannotDeleteExistingRecord() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let first=try record();try c.save(first,select:true)
        var corrupt=try c.reader.snapshot();corrupt.pendingRestore=[first.reference]
        m.bytes=try JSONEncoder().encode(corrupt)
        XCTAssertThrowsError(try c.reconcilePendingRestore(vpnInactive:{true}));XCTAssertNotNil(try repo.read(first.reference))
        XCTAssertThrowsError(try c.reader.isSelected(first.reference))
    }
    @MainActor func testInsertReadbackFailureNeverPublishesMissingRecord() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let original=try record();try c.save(original,select:true);let before=try c.reader.snapshot()
        let fresh=try record();items.onInsert={items.values=items.values.filter{!$0.key.contains(fresh.reference.revision.uuidString)}}
        XCTAssertThrowsError(try c.save(fresh,select:true));items.onInsert=nil
        assertRestoredContent(try c.reader.snapshot(),before);XCTAssertEqual(items.values.count,1)
        XCTAssertNotNil(try repo.read(original.reference))
    }
    @MainActor func testBatchReadbackDriftPreservesUnexpectedJournal() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let first=try record();try c.save(first,select:true)
        let replacementNonce=UUID();var changed:NativeCredentialCatalogReader.Snapshot?
        items.onRead={_ in
            guard changed==nil,var state=try? c.reader.snapshot(),state.pendingRestore != nil else{return}
            state.selectionNonce=replacementNonce;changed=state;m.bytes=try! JSONEncoder().encode(state)
        }
        XCTAssertThrowsError(try c.restore([try record(),try record()],vpnInactive:{true}));items.onRead=nil
        XCTAssertEqual(try c.reader.snapshot(),try XCTUnwrap(changed));XCTAssertEqual(items.values.count,3)
        try c.reconcilePendingRestore(vpnInactive:{true});XCTAssertEqual(items.values.count,1)
        XCTAssertEqual(try c.reader.snapshot().selectionNonce,replacementNonce)
    }
    @MainActor func testRetiredCleanupStopsOnUnexpectedSnapshotBeforeNextDeletion() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record(),b=try record(),active=try record();try c.save(a,select:false);try c.save(b,select:false);try c.save(active,select:true)
        try c.remove(a.reference);try c.remove(b.reference)
        let nonce=UUID();var changed:NativeCredentialCatalogReader.Snapshot?
        items.onRemove={_ in
            guard changed==nil,var state=try? c.reader.snapshot() else{return}
            state.selectionNonce=nonce;changed=state;m.bytes=try! JSONEncoder().encode(state)
        }
        XCTAssertThrowsError(try c.reconcileRetired());items.onRemove=nil
        XCTAssertEqual(try c.reader.snapshot(),try XCTUnwrap(changed));XCTAssertNil(try repo.read(a.reference));XCTAssertNotNil(try repo.read(b.reference));XCTAssertNotNil(try repo.read(active.reference))
        try c.reconcileRetired();XCTAssertEqual(items.values.count,1);XCTAssertEqual(try c.reader.snapshot().selectionNonce,nonce)
    }
    @MainActor func testSelectionRejectsLegacyCollisionAppearingDuringRead() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items)
        var legacy=Set<UUID>();let c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{legacy})
        let a=try record();try c.save(a,select:false);let before=try c.reader.snapshot()
        items.onRead={_ in legacy.insert(a.reference.profileID)}
        XCTAssertThrowsError(try c.select(a.reference));items.onRead=nil
        XCTAssertEqual(try c.reader.snapshot(),before);XCTAssertNotNil(try repo.read(a.reference))
    }
    @MainActor func testLegacyPendingRestoreMigrationPreservesExactJournalAndDeniesOldAuthority() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record(),pending=try record();try c.save(a,select:true);try repo.insert(pending)
        var legacy=try c.reader.snapshot();legacy.version=1;legacy.pendingRestore=[pending.reference]
        m.bytes=try JSONEncoder().encode(legacy);let raw=m.bytes
        XCTAssertNil(try c.reader.selectionAuthority(a.reference))
        XCTAssertThrowsError(try c.reconcilePendingRestore(vpnInactive:{true}));XCTAssertThrowsError(try c.reader.currentRecordsForBackup(repository:repo))
        XCTAssertThrowsError(try c.migrateLegacyForValidation(vpnInactive:{false}));XCTAssertEqual(m.bytes,raw)
        m.fail=true;XCTAssertThrowsError(try c.migrateLegacyForValidation(vpnInactive:{true}));XCTAssertEqual(m.bytes,raw);m.fail=false
        try c.migrateLegacyForValidation(vpnInactive:{true})
        let new=try c.reader.snapshot();XCTAssertEqual(new.version,2);XCTAssertEqual(new.current,legacy.current);XCTAssertEqual(new.pendingRestore,legacy.pendingRestore);XCTAssertNil(new.selectionNonce)
        let writes=m.writes;try c.migrateLegacyForValidation(vpnInactive:{true});XCTAssertEqual(m.writes,writes)
        XCTAssertEqual(items.values.count,2);try c.reconcilePendingRestore(vpnInactive:{true});XCTAssertEqual(items.values.count,1);XCTAssertNil(try c.reader.selectionAuthority(a.reference))
        try c.select(a.reference);XCTAssertNotNil(try c.reader.selectionAuthority(a.reference))
    }
    @MainActor func testLegacyPendingInsertAndUnknownSchemaNeverMutateBeforeMigration() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record(),pending=try record(a.reference.profileID);try c.save(a,select:true);try repo.insert(pending)
        var legacy=try c.reader.snapshot();legacy.version=1;legacy.pendingInsert=pending.reference
        m.bytes=try JSONEncoder().encode(legacy);let raw=m.bytes
        XCTAssertThrowsError(try c.reconcilePendingInsert());XCTAssertThrowsError(try c.remove(a.reference));XCTAssertThrowsError(try c.save(try record(),select:false));XCTAssertEqual(m.bytes,raw);XCTAssertEqual(items.values.count,2)
        legacy.version=3;m.bytes=try JSONEncoder().encode(legacy);let unknown=m.bytes
        XCTAssertThrowsError(try c.migrateLegacyForValidation(vpnInactive:{true}));XCTAssertThrowsError(try c.reader.snapshot());XCTAssertEqual(m.bytes,unknown)
        m.bytes=raw;try c.migrateLegacyForValidation(vpnInactive:{true});try c.reconcilePendingInsert();XCTAssertNil(try repo.read(pending.reference));XCTAssertNotNil(try repo.read(a.reference))
    }
    @MainActor func testMigrationRejectsDriftAndDoesNotMintSelectionAuthority() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record();try c.save(a,select:true);var legacy=try c.reader.snapshot();legacy.version=1;m.bytes=try JSONEncoder().encode(legacy)
        var calls=0;var changed=legacy;changed.selectionNonce=UUID();let changedBytes=try JSONEncoder().encode(changed)
        XCTAssertThrowsError(try c.migrateLegacyForValidation(vpnInactive:{calls+=1;if calls==2{m.bytes=changedBytes};return true}));XCTAssertEqual(m.bytes,changedBytes);XCTAssertNil(try c.reader.selectionAuthority(a.reference))
        try c.migrateLegacyForValidation(vpnInactive:{true});XCTAssertNil(try c.reader.selectionAuthority(a.reference));XCTAssertEqual(try c.reader.snapshot().current,[a.reference])
    }
    @MainActor func testNativeDispatchPreSubmitDriftAndCleanupRetryKeepExactLease() async throws {
        let m=CatalogMemory(),items=RecordMemory(),tickets=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record();try c.save(a,select:true)
        let bridge=NativeSessionLaunchBoundary(reader:c.reader,repository:repo,ticketItems:tickets,legacyIDs:{[]}),gate=NativeOperationGate()
        let intent=try bridge.prepare(reference:a.reference,scope:.syntheticLab,routes:.tunnelOnly,required:[.tcpIPv4],siteExclusions:[],applicationExclusions:[])
        let dispatch=try NativeValidationDispatch(gate:gate,boundary:bridge,intent:intent,owner:UUID())
        XCTAssertThrowsError(try gate.reserve(.start));gate.release(UUID());XCTAssertEqual(gate.active,.nativeValidation)
        var checks=0,starts=0
        XCTAssertThrowsError(try dispatch.submit(checkOwnedAndQuiescent:{checks+=1;return checks==1},start:{_ in starts+=1}))
        XCTAssertEqual(starts,0);XCTAssertFalse(dispatch.attempted);XCTAssertEqual(tickets.values.count,1)
        tickets.failRemove=true;XCTAssertThrowsError(try dispatch.abortBeforeSubmission());XCTAssertEqual(gate.active,.nativeValidation)
        tickets.failRemove=false;try dispatch.abortBeforeSubmission();XCTAssertNil(gate.active);XCTAssertTrue(tickets.values.isEmpty)
    }
    @MainActor func testNativeDispatchAmbiguousStartCannotReleaseOrRetry() async throws {
        let m=CatalogMemory(),items=RecordMemory(),tickets=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record();try c.save(a,select:true)
        let bridge=NativeSessionLaunchBoundary(reader:c.reader,repository:repo,ticketItems:tickets,legacyIDs:{[]}),gate=NativeOperationGate(),owner=UUID()
        let intent=try bridge.prepare(reference:a.reference,scope:.syntheticLab,routes:.tunnelOnly,required:[.tcpIPv4],siteExclusions:[],applicationExclusions:[])
        let dispatch=try NativeValidationDispatch(gate:gate,boundary:bridge,intent:intent,owner:owner)
        var calls=0
        XCTAssertThrowsError(try dispatch.submit(checkOwnedAndQuiescent:{true},start:{options in
            calls+=1
            XCTAssertEqual(options[NativeProviderStartRequest.ownerKey] as? String,owner.uuidString)
            guard case .validation=NativeProviderStartRequest.inspect(configuration:NativeProviderStartRequest.configuration(owner:owner),options:options,validationEnabled:true) else {return XCTFail("not validation")}
            throw NativeValidationDispatch.Failure.invalidState
        }))
        XCTAssertTrue(dispatch.attempted);XCTAssertEqual(calls,1);XCTAssertEqual(gate.active,.nativeValidation)
        XCTAssertThrowsError(try dispatch.abortBeforeSubmission());XCTAssertThrowsError(try dispatch.submit(checkOwnedAndQuiescent:{true},start:{_ in calls+=1}));XCTAssertThrowsError(try gate.reserve(.restore));XCTAssertEqual(calls,1)
    }
    @MainActor func testNativeDispatchRequiresMatchingDrainAndIndependentOffBeforeRelease() async throws {
        let m=CatalogMemory(),items=RecordMemory(),tickets=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record();try c.save(a,select:true)
        let bridge=NativeSessionLaunchBoundary(reader:c.reader,repository:repo,ticketItems:tickets,legacyIDs:{[]}),gate=NativeOperationGate()
        let i=try bridge.prepare(reference:a.reference,scope:.syntheticLab,routes:.tunnelOnly,required:[.tcpIPv4],siteExclusions:[],applicationExclusions:[])
        let d=try NativeValidationDispatch(gate:gate,boundary:bridge,intent:i,owner:UUID())
        try d.submit(checkOwnedAndQuiescent:{true},start:{_ in})
        XCTAssertThrowsError(try d.finishAfterTerminalDrain(osOffAndOwned:{true}))
        let old=try d.requestTerminalDrain(),current=try d.requestTerminalDrain()
        XCTAssertThrowsError(try d.acceptTerminalDrain(.init(request:old,state:.drained)))
        XCTAssertThrowsError(try d.acceptTerminalDrain(.init(request:current,state:.failed)))
        XCTAssertEqual(gate.active,.nativeValidation)
        try d.acceptTerminalDrain(.init(request:current,state:.drained))
        XCTAssertThrowsError(try d.finishAfterTerminalDrain(osOffAndOwned:{false}))
        tickets.failRemove=true;XCTAssertThrowsError(try d.finishAfterTerminalDrain(osOffAndOwned:{true}));XCTAssertEqual(gate.active,.nativeValidation)
        tickets.failRemove=false;var checks=0
        XCTAssertThrowsError(try d.finishAfterTerminalDrain(osOffAndOwned:{checks+=1;return checks==1}));XCTAssertEqual(gate.active,.nativeValidation);XCTAssertTrue(tickets.values.isEmpty)
        try d.finishAfterTerminalDrain(osOffAndOwned:{true});XCTAssertNil(gate.active)
        XCTAssertThrowsError(try d.finishAfterTerminalDrain(osOffAndOwned:{true}));XCTAssertEqual(items.values.count,1)
    }
    @MainActor func testProviderOptionBoundaryNeverFallsBackAndValidatesOneUse() async throws {
        let m=CatalogMemory(),items=RecordMemory(),tickets=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record();try c.save(a,select:true)
        let bridge=NativeSessionLaunchBoundary(reader:c.reader,repository:repo,ticketItems:tickets,legacyIDs:{[]})
        let intent=try bridge.prepare(reference:a.reference,scope:.syntheticLab,routes:.tunnelOnly,required:[.tcpIPv4],siteExclusions:[],applicationExclusions:[])
        var coordinator=TransportBackendCoordinator();guard case .start(let session)=try coordinator.begin(intent.plan) else{return XCTFail("start")}
        let owner=UUID(),launch=try bridge.issue(intent,for:session),config=NativeProviderStartRequest.configuration(owner:owner),opts=launch.validationOptions(owner:owner)
        func denied(_ config:[String:Any]?,_ opts:[String:NSObject]?,_ enabled:Bool=true)->Bool {if case .denied=NativeProviderStartRequest.inspect(configuration:config,options:opts,validationEnabled:enabled){return true};return false}
        XCTAssertTrue(denied(config,opts,false));XCTAssertTrue(denied(config,nil));XCTAssertTrue(denied(nil,opts));XCTAssertTrue(denied(["APLNativeUnknown":true],nil))
        var foreign=opts;foreign[NativeProviderStartRequest.ownerKey]=UUID().uuidString as NSString;XCTAssertTrue(denied(config,foreign))
        var mixed=opts;mixed["requestedByUser"]=NSNumber(value:true);XCTAssertTrue(denied(config,mixed))
        var wrong=opts;wrong[NativeProviderStartRequest.expectedKey]=try TransportNativeCodec.encode(NativeCredentialHandoff.Binding(reference:a.reference,session:.init(epoch:UUID(),generation:1,provider:"rust-xray"),selectionNonce:UUID())) as NSData;XCTAssertTrue(denied(config,wrong))
        XCTAssertEqual(tickets.values.count,1)
        if case .legacy=NativeProviderStartRequest.inspect(configuration:["version":"0.2.0"],options:["requestedByUser":NSNumber(value:true)],validationEnabled:false){}else{XCTFail("legacy rejected")}
        guard case .validation(let request)=NativeProviderStartRequest.inspect(configuration:config,options:opts,validationEnabled:true) else{return XCTFail("validation rejected")}
        XCTAssertEqual(Mirror(reflecting:request).children.count,0)
        let receiver=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{try c.reader.authorizes($0)})
        var inspected=0
        try request.validate(via:receiver,inspectConfiguration:{route,bytes in
            inspected+=1;XCTAssertEqual(route.provider,.rustXray)
            let json=try JSONSerialization.jsonObject(with:bytes) as? [String:Any]
            XCTAssertNotNil(json?["outbounds"]);XCTAssertNotNil(json?["inbounds"])
        });XCTAssertThrowsError(try request.validate(via:receiver));XCTAssertEqual(inspected,1);XCTAssertTrue(tickets.values.isEmpty)
        try bridge.finish(intent);XCTAssertEqual(items.values.count,1)
    }
    @MainActor func testLaunchBoundaryConnectsAllThreeStoredKindsToProviderReceiver() async throws {
        let m=CatalogMemory(),items=RecordMemory(),tickets=RecordMemory(),repo=NativeCredentialRepository(items:items)
        let c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=Curve25519.KeyAgreement.PrivateKey(),b=Curve25519.KeyAgreement.PrivateKey()
        let src="[Interface]\nPrivateKey=\(a.rawRepresentation.base64EncodedString())\nAddress=10.0.0.2/32, fd00::2/128\nDNS=192.0.2.53\n[Peer]\nPublicKey=\(b.publicKey.rawRepresentation.base64EncodedString())\nAllowedIPs=0.0.0.0/0, ::/0\nEndpoint=192.0.2.42:51820"
        let awg=src.replacingOccurrences(of:"[Peer]",with:"Jc=0\nJmin=0\nJmax=0\nS1=15\nS2=18\nH1=123456\nH2=67543\nH3=123123\nH4=32345\n[Peer]")
        let key=b.publicKey.rawRepresentation.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        let vless="vless://\(UUID().uuidString.lowercased())@192.0.2.42:443?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk=\(key)&sid=abcd"
        let records=[try NativeCredentialRecord.create(profileID:UUID(),expected:.wireGuard,source:src),try NativeCredentialRecord.create(profileID:UUID(),expected:.amneziaWG1,source:awg),try NativeCredentialRecord.create(profileID:UUID(),expected:.vlessReality,source:vless)]
        let bridge=NativeSessionLaunchBoundary(reader:c.reader,repository:repo,ticketItems:tickets,legacyIDs:{[]})
        let receiverHandoff=NativeCredentialHandoff(items:tickets,repository:repo,authorizes:{try c.reader.authorizes($0)})
        var coordinator=TransportBackendCoordinator()
        for r in records {
            try c.save(r,select:true)
            let intent=try bridge.prepare(reference:r.reference,scope:.syntheticLab,routes:.tunnelOnly,required:[.tcpIPv4],siteExclusions:[],applicationExclusions:[])
            guard case .start(let session)=try coordinator.begin(intent.plan) else {return XCTFail("expected start")}
            let expected=try intent.expectedBinding(for:session),launch=try bridge.issue(intent,for:session)
            XCTAssertEqual(Mirror(reflecting:launch).children.count,0)
            XCTAssertFalse(String(decoding:launch.ticketBytes,as:UTF8.self).contains("192.0.2.42"))
            XCTAssertThrowsError(try bridge.issue(intent,for:session))
            var receiver=try NativeCredentialReceiver(expected:expected,provider:r.reference.kind.provider)
            let ok=try receiver.consumeForValidation(launch.ticketBytes,via:receiverHandoff){route,bytes in route.provider==r.reference.kind.provider && route.remoteAddress=="192.0.2.42" && !bytes.isEmpty}
            XCTAssertTrue(ok);XCTAssertTrue(tickets.values.isEmpty)
            try bridge.finish(intent)
            _=try coordinator.ready(session.token,provider:session.plan.provider);_=try coordinator.requestStop(session.token)
            _=try coordinator.acknowledgeNativeDrain(session.token);_=try coordinator.acknowledgeOSDisconnected(session.token)
        }
        XCTAssertEqual(items.values.count,3);XCTAssertEqual(coordinator.phase,.idle)
    }
    @MainActor func testLaunchBoundaryRejectsProductionCapabilitiesAndStaleSelection() async throws {
        let m=CatalogMemory(),items=RecordMemory(),tickets=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record();try c.save(a,select:true)
        let bridge=NativeSessionLaunchBoundary(reader:c.reader,repository:repo,ticketItems:tickets,legacyIDs:{[]})
        func prepare(_ scope:TransportBackendPlan.Scope = .syntheticLab,_ required:Set<TransportProbeCapability> = [.tcpIPv4],_ exclusions:[String] = []) throws -> NativeSessionLaunchBoundary.Intent {try bridge.prepare(reference:a.reference,scope:scope,routes:.tunnelOnly,required:required,siteExclusions:exclusions,applicationExclusions:[])}
        XCTAssertThrowsError(try prepare(.production));XCTAssertThrowsError(try prepare(.syntheticLab,[.dns]));XCTAssertThrowsError(try prepare(.syntheticLab,[.tcpIPv4],["example.com"]))
        let intent=try prepare();var coordinator=TransportBackendCoordinator();guard case .start(let session)=try coordinator.begin(intent.plan) else{return XCTFail("start")}
        try c.select(a.reference);XCTAssertThrowsError(try bridge.issue(intent,for:session));XCTAssertTrue(tickets.values.isEmpty)
        XCTAssertThrowsError(try bridge.issue(intent,for:session))
    }
    @MainActor func testLaunchBoundaryWrongSessionAndFailedCleanupRetainsOwnership() async throws {
        let m=CatalogMemory(),items=RecordMemory(),tickets=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record(),b=try record();try c.save(a,select:true);try c.save(b,select:false)
        let bridge=NativeSessionLaunchBoundary(reader:c.reader,repository:repo,ticketItems:tickets,legacyIDs:{[]})
        func prepare() throws -> NativeSessionLaunchBoundary.Intent {try bridge.prepare(reference:a.reference,scope:.syntheticLab,routes:.tunnelOnly,required:[.tcpIPv4],siteExclusions:[],applicationExclusions:[])}
        let bad=try prepare();let other=try TransportBackendPlan.prepare(profileID:b.reference.profileID,revision:b.reference.revision,protocol:.wireGuard,scope:.syntheticLab,routes:.tunnelOnly,required:[.tcpIPv4]);var unrelated=TransportBackendCoordinator()
        guard case .start(let wrong)=try unrelated.begin(other) else{return XCTFail("start")}
        XCTAssertThrowsError(try bridge.issue(bad,for:wrong));XCTAssertTrue(tickets.values.isEmpty)
        let intent=try prepare();var coordinator=TransportBackendCoordinator();guard case .start(let session)=try coordinator.begin(intent.plan) else{return XCTFail("start")}
        _=try bridge.issue(intent,for:session);tickets.failRemove=true
        XCTAssertThrowsError(try bridge.finish(intent));XCTAssertThrowsError(try prepare());XCTAssertEqual(tickets.values.count,1)
        tickets.failRemove=false;try bridge.finish(intent);XCTAssertTrue(tickets.values.isEmpty);XCTAssertEqual(items.values.count,2)
    }
    @MainActor func testNativeLibraryMetadataProjectionBlocksUnacceptedStates() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        let a=try record(),b=try record();try c.save(a,select:true);try c.save(b,select:false)
        func states(_ ids:Set<UUID> = [],_ exclusions:Bool = false) throws -> [NativeProfilePresentation.State] {try NativeProfilePresentation.read(c.reader,legacyIDs:ids,hasExclusions:exclusions).rows.map(\.state)}
        XCTAssertEqual(try states([a.reference.profileID]),[.legacyCollision,.reviewOnly]);XCTAssertEqual(try states([],true),[.unsupportedPolicy,.unsupportedPolicy])
        var snapshot=try c.reader.snapshot();snapshot.pendingInsert=try record().reference;m.bytes=try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try states(),[.recoveryRequired,.recoveryRequired])
        snapshot.version=1;m.bytes=try JSONEncoder().encode(snapshot);XCTAssertEqual(try states(),[.migrationRequired,.migrationRequired])
        snapshot.version=999;m.bytes=try JSONEncoder().encode(snapshot);XCTAssertThrowsError(try states())
        XCTAssertEqual(items.values.count,2)
    }
    @MainActor func testCorruptCatalogAndLegacyCollisionFailClosed() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),r=try record()
        let c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[r.reference.profileID]})
        XCTAssertThrowsError(try c.save(r,select:true));XCTAssertTrue(items.values.isEmpty)
        m.bytes=Data([1]);let d=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        XCTAssertThrowsError(try d.save(r,select:true));XCTAssertThrowsError(try d.reader.isSelected(r.reference));XCTAssertEqual(m.bytes,Data([1]));XCTAssertTrue(items.values.isEmpty)
    }
}
