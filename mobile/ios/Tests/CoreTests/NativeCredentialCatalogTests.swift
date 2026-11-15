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
    func insert(account:String,bytes:Data) throws { guard values[account] == nil else {throw Failure.denied};values[account] = bytes }
    func read(account:String) throws -> Data? { values[account] }
    func remove(account:String) throws -> Bool { if failRemove {throw Failure.denied};return values.removeValue(forKey:account) != nil }
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
        let reader=c.reader, h=NativeCredentialHandoff(items:tickets,repository:repo,isSelected:{try reader.isSelected($0)})
        let binding=NativeCredentialHandoff.Binding(reference:first.reference,session:.init(epoch:UUID(),generation:1,provider:"rust-xray"))
        let ticket=try h.issue(first,binding:binding)
        let second=try record(first.reference.profileID);try c.save(second,select:true)
        XCTAssertNotNil(try repo.read(first.reference));XCTAssertThrowsError(try h.redeem(ticket,expected:binding))
        XCTAssertTrue(try reader.isSelected(second.reference));XCTAssertEqual(try reader.snapshot().retired,[first.reference])
        try c.reconcileRetired();XCTAssertNil(try repo.read(first.reference));XCTAssertNotNil(try repo.read(second.reference))
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
    @MainActor func testCorruptCatalogAndLegacyCollisionFailClosed() async throws {
        let m=CatalogMemory(),items=RecordMemory(),repo=NativeCredentialRepository(items:items),r=try record()
        let c=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[r.reference.profileID]})
        XCTAssertThrowsError(try c.save(r,select:true));XCTAssertTrue(items.values.isEmpty)
        m.bytes=Data([1]);let d=NativeCredentialCatalog(storage:m,repository:repo,legacyIDs:{[]})
        XCTAssertThrowsError(try d.save(r,select:true));XCTAssertThrowsError(try d.reader.isSelected(r.reference));XCTAssertEqual(m.bytes,Data([1]));XCTAssertTrue(items.values.isEmpty)
    }
}
