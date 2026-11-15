import Foundation
import CryptoKit
import XCTest
@testable import ArvectumProxyLauncherIOSCore

final class NativeProfileBackupCodecTests: XCTestCase {
    private let password="Synthetic-backup-passphrase-2026"
    private func records() throws -> [NativeCredentialRecord] {
        let a=Curve25519.KeyAgreement.PrivateKey(),b=Curve25519.KeyAgreement.PrivateKey()
        let wg="[Interface]\nPrivateKey=\(a.rawRepresentation.base64EncodedString())\nAddress=10.0.0.2/32, fd00::2/128\nDNS=192.0.2.53\n[Peer]\nPublicKey=\(b.publicKey.rawRepresentation.base64EncodedString())\nAllowedIPs=0.0.0.0/0, ::/0\nEndpoint=192.0.2.42:51820"
        let awg=wg.replacingOccurrences(of:"[Peer]",with:"Jc=0\nJmin=0\nJmax=0\nS1=15\nS2=18\nH1=123456\nH2=67543\nH3=123123\nH4=32345\n[Peer]")
        let key=b.publicKey.rawRepresentation.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        let vless="vless://\(UUID().uuidString.lowercased())@192.0.2.43:443?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk=\(key)&sid=abcd"
        return try [(wg,TransportProtocol.wireGuard),(awg,.amneziaWG1),(vless,.vlessReality)].map {try NativeCredentialRecord.create(profileID:UUID(),expected:$0.1,source:$0.0)}
    }
    func testAllKindsEncryptedRoundTripAndRandomSalt() throws {
        let source=try records(), sealed=try NativeProfileBackupCodec.seal(source,password:password)
        XCTAssertNotEqual(sealed,try NativeProfileBackupCodec.seal(source,password:password))
        let text=String(decoding:sealed,as:UTF8.self)
        for r in source {XCTAssertFalse(text.contains(r.reference.profileID.uuidString));XCTAssertFalse(text.contains(r.reference.kind.rawValue))}
        XCTAssertFalse(text.contains("192.0.2.42"));XCTAssertFalse(text.contains("PrivateKey"))
        let restored=try NativeProfileBackupCodec.open(sealed,password:password)
        XCTAssertEqual(try restored.map{try $0.encoded()},try source.map{try $0.encoded()})
    }
    func testWrongPasswordTamperAndHeaderRelabel() throws {
        let sealed=try NativeProfileBackupCodec.seal(records(),password:password)
        XCTAssertThrowsError(try NativeProfileBackupCodec.open(sealed,password:"Incorrect-passphrase"))
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:sealed) as? [String:Any])
        let b64=try XCTUnwrap(json["ciphertext"] as? String);var bytes=try XCTUnwrap(Data(base64Encoded:b64));bytes[16] ^= 1;json["ciphertext"]=bytes.base64EncodedString()
        XCTAssertThrowsError(try NativeProfileBackupCodec.open(JSONSerialization.data(withJSONObject:json),password:password))
        json["ciphertext"]=b64;json["format"]="arvectum.apl.encrypted-profiles"
        XCTAssertThrowsError(try ProfileBackupCodec.open(JSONSerialization.data(withJSONObject:json),password:password))
        XCTAssertThrowsError(try ProfileBackupCodec.open(sealed,password:password))
    }
    func testRestoreMintsIDsWithoutChangingConfig() throws {
        let original=try records(), ids=Set(original.map(\.reference.profileID))
        let restored=try NativeProfileBackupCodec.prepareRestore(original,existingNativeIDs:ids,legacyIDs:[UUID()])
        XCTAssertTrue(ids.isDisjoint(with:Set(restored.map(\.reference.profileID))))
        for (a,b) in zip(original,restored) {
            XCTAssertNotEqual(a.reference.revision,b.reference.revision);XCTAssertEqual(a.reference.kind,b.reference.kind)
            XCTAssertEqual(try a.compile().0.withEngineConfiguration{$0},try b.compile().0.withEngineConfiguration{$0})
        }
    }
    func testNativePasswordBoundUsesBytesNotGraphemeCount() throws {
        let source=try records()
        let oversized=String(repeating:"a\u{0301}",count:11)+"a"+String(repeating:"\u{0301}",count:3000)
        XCTAssertEqual(oversized.count,12)
        XCTAssertGreaterThan(oversized.utf8.count,NativeProfileBackupCodec.maxPasswordBytes)
        XCTAssertThrowsError(try NativeProfileBackupCodec.seal(source,password:oversized)) { error in
            guard case ProfileBackupError.weakPassword=error else{return XCTFail("wrong error")}
        }
        let sealed=try NativeProfileBackupCodec.seal(source,password:password)
        XCTAssertThrowsError(try NativeProfileBackupCodec.open(sealed,password:oversized)) { error in
            guard case ProfileBackupError.weakPassword=error else{return XCTFail("wrong error")}
        }
        let unicode="Синтетический-пароль-2026"
        XCTAssertEqual(try NativeProfileBackupCodec.open(NativeProfileBackupCodec.seal(source,password:unicode),password:unicode).count,3)
    }
    func testOversizedCiphertextRejectedBeforePasswordDerivation() throws {
        let sealed=try NativeProfileBackupCodec.seal(records(),password:password)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:sealed) as? [String:Any])
        json["ciphertext"]=Data(repeating:0,count:ProfileBackupCodec.maxFileBytes/2+29).base64EncodedString()
        let malformed=try JSONSerialization.data(withJSONObject:json)
        XCTAssertLessThan(malformed.count,ProfileBackupCodec.maxFileBytes)
        XCTAssertThrowsError(try NativeProfileBackupCodec.open(malformed,password:"short")) {error in
            guard case ProfileBackupError.invalidFile=error else{return XCTFail("expected pre-KDF size rejection")}
        }
    }
    func testInvalidRecordsCapacityAndLegacyFormatRejected() throws {
        let source=try records();XCTAssertThrowsError(try NativeProfileBackupCodec.seal([],password:password));XCTAssertThrowsError(try NativeProfileBackupCodec.seal([source[0],source[0]],password:password))
        XCTAssertThrowsError(try NativeProfileBackupCodec.prepareRestore(source,existingNativeIDs:Set((0..<30).map{_ in UUID()}),legacyIDs:[]))
        XCTAssertThrowsError(try NativeProfileBackupCodec.seal(source,password:"short"))
        let p=ProxyProfile(name:"Legacy",host:"192.0.2.99",port:8080,type:.http)
        let legacy=try ProfileBackupCodec.seal(.init(profiles:[.init(profile:p,password:nil)],favorites:[],groups:[:]),password:password)
        XCTAssertThrowsError(try NativeProfileBackupCodec.open(legacy,password:password))
    }
}
