// Independent synthetic fixture only; never reads a profile store or credentials.
import Foundation
import CryptoKit
import CommonCrypto
guard CommandLine.arguments.count==2, CommandLine.arguments[1].hasSuffix("/APL-QA-Negative.json") else {fatalError("Specify a fresh disposable QA fixture path ending in /APL-QA-Negative.json")}
let key1=Curve25519.KeyAgreement.PrivateKey(),key2=Curve25519.KeyAgreement.PrivateKey()
let source="[Interface]\nPrivateKey=\(key1.rawRepresentation.base64EncodedString())\nAddress=10.0.0.2/32, fd00::2/128\nDNS=192.0.2.53\n[Peer]\nPublicKey=\(key2.publicKey.rawRepresentation.base64EncodedString())\nAllowedIPs=0.0.0.0/0, ::/0\nEndpoint=192.0.2.42:51820\n"
let ref=["profileID":UUID().uuidString,"revision":UUID().uuidString,"kind":"wireGuard"]
let record=try JSONSerialization.data(withJSONObject:["version":1,"reference":ref,"source":source])
let payload=try JSONSerialization.data(withJSONObject:["version":1,"records":[["reference":ref,"record":record.base64EncodedString()]]])
let magic="arvectum.apl.encrypted-native-profiles",pass="Synthetic-QA-Correct-2026",salt=Data((0..<16).map{_ in UInt8.random(in:0...255)})
var key=Data(count:32)
let code=pass.withCString { p in salt.withUnsafeBytes { s in key.withUnsafeMutableBytes { k in CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),p,pass.utf8.count,s.bindMemory(to:UInt8.self).baseAddress,salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),210000,k.bindMemory(to:UInt8.self).baseAddress,32)}}}
precondition(code==kCCSuccess)
let ciphertext=try AES.GCM.seal(payload,using:SymmetricKey(data:key),authenticating:Data(magic.utf8)).combined!
let envelope=try JSONSerialization.data(withJSONObject:["format":magic,"version":1,"kdf":"PBKDF2-HMAC-SHA256","iterations":210000,"salt":salt.base64EncodedString(),"ciphertext":ciphertext.base64EncodedString()])
try envelope.write(to:URL(fileURLWithPath:CommandLine.arguments[1]),options:.withoutOverwriting)
