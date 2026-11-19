import Foundation
import CryptoKit
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativeProfileReviewSessionTests:XCTestCase {
    private func vless()->String {
        let key=Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        return "vless://\(UUID().uuidString.lowercased())@192.0.2.43:443?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk=\(key)&sid=abcd"
    }
    func testFileLifecycleRejectsOldCallbackAfterBackgroundAndReopen() throws {
        var g=NativeReviewFileLifecycle()
        XCTAssertNil(g.begin(.backup));g.appear()
        let old=try XCTUnwrap(g.begin(.configuration(.wireGuard)))
        XCTAssertNil(g.begin(.backup));g.leave();XCTAssertNil(g.consume(old))
        g.appear();let new=try XCTUnwrap(g.begin(.configuration(.vlessReality)))
        XCTAssertNil(g.consume(old));XCTAssertEqual(g.pending,new)
        XCTAssertEqual(g.consume(new),.configuration(.vlessReality));XCTAssertNil(g.consume(new))
    }
    func testCancelledPanelCannotConsumeNewExportAndActionsAreBound() throws {
        var g=NativeReviewFileLifecycle();g.appear()
        let first=try XCTUnwrap(g.begin(.backup));g.invalidate()
        let second=try XCTUnwrap(g.begin(.export))
        XCTAssertNotEqual(first.id,second.id);XCTAssertNil(g.consume(first));XCTAssertEqual(g.consume(second),.export)
        g.leave();XCTAssertNil(g.begin(.export))
    }
    func testBoundedNativeFileReaderUsesActualFiles() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);defer{try? FileManager.default.removeItem(at:root)}
        func write(_ name:String,_ bytes:Data)throws->URL {let p=root.appendingPathComponent(name);try bytes.write(to:p);return p}
        let a=vless(),b=vless(),first=try write("one.txt",Data(a.utf8)),second=try write("two.txt",Data(b.utf8))
        XCTAssertEqual(try NativeAutomaticImport.readSources([first,second]),[a,b]);XCTAssertEqual(try NativeAutomaticImport.prepare(NativeAutomaticImport.readSources([first,second])).count,2)
        let huge=try write("huge.txt",Data(repeating:65,count:NativeAutomaticImport.maxBytes))
        XCTAssertThrowsError(try NativeAutomaticImport.readSources([first,huge]))
        XCTAssertThrowsError(try NativeAutomaticImport.readSource(first,limit:a.utf8.count-1))
        XCTAssertEqual(try NativeAutomaticImport.readSource(first,limit:a.utf8.count),a)
        let invalid=try write("invalid",Data([0xff,0xfe]));XCTAssertThrowsError(try NativeAutomaticImport.readSources([first,invalid]))
        XCTAssertThrowsError(try NativeAutomaticImport.readSources(Array(repeating:first,count:33)))
        XCTAssertThrowsError(try NativeAutomaticImport.readSources([]))
    }
    @MainActor func testAutomaticRehearsalRemovalConfirmationAndEncryptedRemainingRecords()async throws {
        var now=100.0;let s=NativeProfileReviewSession(elapsed:{now}),other=NativeProfileReviewSession()
        let a=vless(),b=vless();let first=try s.previewAutomatic([a+"\n"+b]);XCTAssertEqual(first.count,2);XCTAssertEqual(try s.counts().total,0)
        _=try s.addToRehearsal(first);let rows=try s.presentation().rows;_ = try s.selectForReview(rows[0].reference)
        let old=try s.prepareRemoval(rows[0].reference);s.cancelReview();XCTAssertThrowsError(try s.confirmRemoval(old));XCTAssertEqual(try s.counts().total,2)
        let invalidated=try s.prepareRemoval(rows[0].reference);_ = try s.previewAutomatic([vless()]);XCTAssertThrowsError(try s.confirmRemoval(invalidated))
        let expired=try s.prepareRemoval(rows[0].reference);now+=300;XCTAssertThrowsError(try s.confirmRemoval(expired))
        let actual=try s.prepareRemoval(rows[0].reference);try s.confirmRemoval(actual);XCTAssertThrowsError(try s.confirmRemoval(actual))
        XCTAssertEqual(try s.presentation().rows.map(\.reference),[rows[1].reference]);XCTAssertFalse(try s.presentation().rows[0].selected)
        let pass="Synthetic-strong-password",data=try s.encryptedBackup(password:pass);let review=try other.previewBackup(data,password:pass);XCTAssertEqual(review.count,1);_ = try other.addToRehearsal(review)
        let close=try s.prepareRemoval(rows[1].reference);s.clear();XCTAssertThrowsError(try s.confirmRemoval(close));XCTAssertEqual(try s.counts().total,0);XCTAssertEqual(try other.counts().total,1)
    }
    @MainActor func testPreviewOnlyUntilConfirmationAndEncryptedRoundTrip() async throws {
        let a=NativeProfileReviewSession(),b=NativeProfileReviewSession(),password="Synthetic-strong-password"
        let summary=try a.previewSource(vless(),kind:.vlessReality)
        XCTAssertEqual(summary.vless,1);XCTAssertEqual(try a.counts().total,0)
        XCTAssertEqual(try a.addToRehearsal(summary).total,1)
        XCTAssertThrowsError(try a.addToRehearsal(summary))
        let encrypted=try a.encryptedBackup(password:password)
        XCTAssertFalse(String(decoding:encrypted,as:UTF8.self).contains("192.0.2.43"))
        let restored=try b.previewBackup(encrypted,password:password)
        XCTAssertEqual(restored.vless,1);XCTAssertEqual(try b.counts().total,0)
        XCTAssertEqual(try b.addToRehearsal(restored).vless,1)
        a.clear();XCTAssertEqual(try a.counts().total,0);XCTAssertEqual(try b.counts().total,1)
    }
    @MainActor func testMixedProtocolsAndIndependentRestore() async throws {
        let a=Curve25519.KeyAgreement.PrivateKey(),b=Curve25519.KeyAgreement.PrivateKey()
        let wg="[Interface]\nPrivateKey=\(a.rawRepresentation.base64EncodedString())\nAddress=10.0.0.2/32, fd00::2/128\nDNS=192.0.2.53\n[Peer]\nPublicKey=\(b.publicKey.rawRepresentation.base64EncodedString())\nAllowedIPs=0.0.0.0/0, ::/0\nEndpoint=192.0.2.42:51820"
        let awg=wg.replacingOccurrences(of:"[Peer]",with:"Jc=0\nJmin=0\nJmax=0\nS1=15\nS2=18\nH1=123456\nH2=67543\nH3=123123\nH4=32345\n[Peer]")
        let s=NativeProfileReviewSession(),target=NativeProfileReviewSession(),p="Synthetic-strong-password"
        _=try s.addToRehearsal(s.previewSource(wg,kind:.wireGuard))
        _=try s.addToRehearsal(s.previewSource(awg,kind:.amneziaWG1))
        _=try s.addToRehearsal(s.previewSource(vless(),kind:.vlessReality))
        let expected=NativeProfileReviewSession.Counts(wireGuard:1,amneziaWG1:1,vless:1)
        XCTAssertEqual(try s.counts(),expected)
        let bytes=try s.encryptedBackup(password:p),review=try target.previewBackup(bytes,password:p)
        XCTAssertEqual(review.count,3);XCTAssertEqual(try target.counts().total,0)
        XCTAssertEqual(try target.addToRehearsal(review),expected)
        s.clear();XCTAssertEqual(try target.counts(),expected)
    }
    @MainActor func testLibrarySelectionOnlyForReviewAndStaleRowCannotReturn() async throws {
        let s=NativeProfileReviewSession()
        _=try s.addToRehearsal(s.previewSource(vless(),kind:.vlessReality))
        _=try s.addToRehearsal(s.previewSource(vless(),kind:.vlessReality))
        let rows=try s.presentation().rows
        XCTAssertEqual(rows.map(\.number),[1,2]);XCTAssertTrue(rows.allSatisfy{$0.canReview && !$0.canConnect && !$0.selected})
        let preview=try s.previewSource(vless(),kind:.vlessReality)
        let selected=try s.selectForReview(rows[0].reference)
        XCTAssertEqual(selected.rows.filter(\.selected).map(\.id),[rows[0].id]);XCTAssertThrowsError(try s.addToRehearsal(preview))
        XCTAssertThrowsError(try s.selectForReview(rows[1].reference,legacyIDs:[rows[1].id]))
        XCTAssertThrowsError(try s.selectForReview(rows[1].reference,hasExclusions:true))
        XCTAssertEqual(try s.presentation().rows.filter(\.selected).map(\.id),[rows[0].id])
        s.clear();XCTAssertThrowsError(try s.selectForReview(rows[0].reference));XCTAssertEqual(try s.presentation(),.empty)
    }
    @MainActor func testInvalidInputCancelAndExpiryNeverCommit() async throws {
        var clock=100.0;let session=NativeProfileReviewSession(elapsed:{clock})
        let first=try session.previewSource(vless(),kind:.vlessReality)
        XCTAssertThrowsError(try session.previewSource("invalid",kind:.vlessReality));XCTAssertThrowsError(try session.addToRehearsal(first))
        let second=try session.previewSource(vless(),kind:.vlessReality);session.cancelReview();XCTAssertThrowsError(try session.addToRehearsal(second))
        let third=try session.previewSource(vless(),kind:.vlessReality);clock+=300;XCTAssertThrowsError(try session.addToRehearsal(third))
        XCTAssertEqual(try session.counts().total,0);XCTAssertThrowsError(try session.encryptedBackup(password:"Synthetic-strong-password"))
    }
    @MainActor func testAuthenticationRetryAndCancellationPreserveExactSelectedProfile() async throws {
        let source=NativeProfileReviewSession(),target=NativeProfileReviewSession(),password="Synthetic-correct-2026"
        _=try source.addToRehearsal(source.previewAutomatic([vless()]))
        _=try target.addToRehearsal(target.previewAutomatic([vless()]))
        let ref=try XCTUnwrap(target.presentation().rows.first).reference
        let baseline=try target.selectForReview(ref),bytes=try source.encryptedBackup(password:password)
        let old=try target.previewBackup(bytes,password:password)
        XCTAssertThrowsError(try target.previewBackup(bytes,password:"Synthetic-wrong-2026")) {
            guard case ProfileBackupError.authenticationFailed=$0 else {return XCTFail("Unexpected error type")}
        }
        XCTAssertThrowsError(try target.addToRehearsal(old));XCTAssertEqual(try target.presentation(),baseline)
        let retry=try target.previewBackup(bytes,password:password);XCTAssertEqual(retry.count,1);XCTAssertNotEqual(retry.id,old.id)
        target.cancelReview();XCTAssertThrowsError(try target.addToRehearsal(retry));XCTAssertEqual(try target.presentation(),baseline)
        let confirmed=try target.previewBackup(bytes,password:password);_ = try target.addToRehearsal(confirmed)
        XCTAssertEqual(try target.presentation().rows.filter(\.selected).map(\.reference),[ref]);XCTAssertEqual(try target.counts().total,2)
    }
    @MainActor func testWrongBackupPasswordAndCloseInvalidatePending() async throws {
        let session=NativeProfileReviewSession(),p="Synthetic-strong-password"
        _=try session.addToRehearsal(session.previewSource(vless(),kind:.vlessReality))
        let bytes=try session.encryptedBackup(password:p),pending=try session.previewBackup(bytes,password:p)
        XCTAssertThrowsError(try session.previewBackup(bytes,password:"Wrong-password-2026"));XCTAssertThrowsError(try session.addToRehearsal(pending))
        XCTAssertEqual(try session.counts().total,1)
        let next=try session.previewBackup(bytes,password:p);session.clear();XCTAssertThrowsError(try session.addToRehearsal(next));XCTAssertEqual(try session.counts().total,0)
    }
}
