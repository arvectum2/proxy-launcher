import Foundation
import CryptoKit
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativeProfileReviewSessionTests:XCTestCase {
    private func vless()->String {
        let key=Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        return "vless://\(UUID().uuidString.lowercased())@192.0.2.43:443?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk=\(key)&sid=abcd"
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
    @MainActor func testInvalidInputCancelAndExpiryNeverCommit() async throws {
        var clock=100.0;let session=NativeProfileReviewSession(elapsed:{clock})
        let first=try session.previewSource(vless(),kind:.vlessReality)
        XCTAssertThrowsError(try session.previewSource("invalid",kind:.vlessReality));XCTAssertThrowsError(try session.addToRehearsal(first))
        let second=try session.previewSource(vless(),kind:.vlessReality);session.cancelReview();XCTAssertThrowsError(try session.addToRehearsal(second))
        let third=try session.previewSource(vless(),kind:.vlessReality);clock+=300;XCTAssertThrowsError(try session.addToRehearsal(third))
        XCTAssertEqual(try session.counts().total,0);XCTAssertThrowsError(try session.encryptedBackup(password:"Synthetic-strong-password"))
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
