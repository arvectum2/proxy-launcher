// Offline acceptance against exact native binary, no engine start or VPN.
import Foundation
import CryptoKit
import LibXray

@main struct NativeVLESSRecordValidation {
    private static func invoke(_ bytes: Data) throws -> Data {
        guard let input=strdup(String(decoding:bytes,as:UTF8.self)) else {throw Failure.rejected}
        defer {free(input)}
        guard let result=CGoInvoke(input) else {throw Failure.rejected}
        defer {CGoFree(result)}
        let size=strnlen(result,65537)
        guard size <= 65536 else {throw Failure.rejected}
        let data=Data(bytes:result,count:size)
        guard let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any], obj["success"] as? Bool == true else {throw Failure.rejected}
        return data
    }
    enum Failure:Error {case rejected}
    static func main() throws {
        for flow in [false,true] {
            let key=Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
            let link="vless://\(UUID().uuidString.lowercased())@192.0.2.42:443?encryption=none&security=reality&type=tcp&sni=example.com&fp=chrome&pbk=\(key)&sid=abcd"+(flow ? "&flow=xtls-rprx-vision" : "")
            let record=try NativeCredentialRecord.create(profileID:UUID(),expected:.vlessReality,source:link)
            let restored=try NativeCredentialRecord.decode(record.encoded(),expected:record.reference)
            let (compiled,route)=try restored.compile()
            guard case .vlessTCP4(let plan)=route,plan.required == [.tcpIPv4] else {throw Failure.rejected}
            let candidate=try VLESSRealityShareLink.parse(link)
            let checked=try XrayVLESSRuntimeConfig.prepare(candidate:candidate,converterResponse:invoke(candidate.conversionRequest()),socksPort:39879)
            guard compiled.withEngineConfiguration({$0}) == checked else {throw Failure.rejected}
            let req=try JSONSerialization.data(withJSONObject:["apiVersion":3,"method":"testXray","payload":["xrayJson":String(decoding:checked,as:UTF8.self)]])
            _ = try invoke(req)
        }
        print("PINNED_VLESS_RECORD_NATIVE_CONFIG_ACCEPTED_2_OF_2")
    }
}
