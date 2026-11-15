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
    private func record(_ id:UUID = UUID()) throws -> NativeCredentialRecord {
        let a=Curve25519.KeyAgreement.PrivateKey(),b=Curve25519.KeyAgreement.PrivateKey()
        let source="[Interface]\nPrivateKey=\(a.rawRepresentation.base64EncodedString())\nAddress=10.0.0.2/32, fd00::2/128\nDNS=192.0.2.53\n[Peer]\nPublicKey=\(b.publicKey.rawRepresentation.base64EncodedString())\nAllowedIPs=0.0.0.0/0, ::/0\nEndpoint=192.0.2.42:51820"
        return try .create(profileID:id,expected:.wireGuard,source:source)
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
        XCTAssertThrowsError(try c.restore(incoming,vpnInactive:{true}));XCTAssertEqual(try c.reader.snapshot(),before);XCTAssertEqual(items.values.count,1)
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
        XCTAssertEqual(try c.reader.snapshot(),before);XCTAssertEqual(items.values.count,1)
    }
    @MainActor func testBatchVPNBecomesActiveDuringInsertDefersRecovery() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        var inactive=true;items.onInsert={inactive=false}
        XCTAssertThrowsError(try c.restore([try record(),try record()],vpnInactive:{inactive}));XCTAssertEqual(items.values.count,1)
        XCTAssertEqual(try c.reader.snapshot().current,[]);XCTAssertEqual(try c.reader.snapshot().pendingRestore?.count,2)
        inactive=true;try c.reconcilePendingRestore(vpnInactive:{inactive});XCTAssertEqual(try c.reader.snapshot(),.empty);XCTAssertTrue(items.values.isEmpty)
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
        m.fail=false;try c.reconcilePendingRestore(vpnInactive:{true});XCTAssertEqual(try c.reader.snapshot(),old)
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
        XCTAssertEqual(try c.reader.snapshot(),before);XCTAssertEqual(items.values.count,1)
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
    @MainActor func testCorruptCatalogAndLegacyCollisionFailClosed() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),r=try record()
        let c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[r.reference.profileID]})
        XCTAssertThrowsError(try c.save(r,select:true));XCTAssertTrue(items.values.isEmpty)
        m.bytes=Data([1]);let d=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        XCTAssertThrowsError(try d.save(r,select:true));XCTAssertThrowsError(try d.reader.isSelected(r.reference));XCTAssertEqual(m.bytes,Data([1]));XCTAssertTrue(items.values.isEmpty)
    }
}
