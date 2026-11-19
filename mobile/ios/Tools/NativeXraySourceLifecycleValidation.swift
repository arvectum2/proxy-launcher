// Standalone loopback-only ABI/lifecycle validation. No actual VPN settings,
// real credentials, external peer, user data or forwarding requests.
import Foundation
import CryptoKit
import LibXray
import Darwin

@main struct NativeXraySourceLifecycleValidation {
    enum Failure: Error {case invalidResponse, unexpectedState, socketUnavailable}
    private static func call(_ method: String, config: Data? = nil) throws -> [String:Any] {
        var req:[String:Any] = ["apiVersion":3,"method":method]
        if let config {req["payload"] = ["xrayJson":String(decoding:config,as:UTF8.self)]}
        let bytes=try JSONSerialization.data(withJSONObject:req)
        guard let input=strdup(String(decoding:bytes,as:UTF8.self)) else {throw Failure.invalidResponse}
        defer {free(input)}
        guard let reply=CGoInvoke(input) else {throw Failure.invalidResponse}
        defer {CGoFree(reply)}
        let size=strnlen(reply,65537)
        guard size<=65536,let object=try JSONSerialization.jsonObject(with:Data(bytes:reply,count:size)) as? [String:Any], object["success"] is Bool else {throw Failure.invalidResponse}
        return object
    }
    private static func state() throws -> Bool {
        let r=try call("getXrayState")
        guard r["success"] as? Bool == true,let b=(r["data"] as? [String:Any])?["running"] as? Bool else {throw Failure.invalidResponse};return b
    }
    private static func require(_ condition: Bool) throws {guard condition else {throw Failure.unexpectedState}}
    private static func localSocket(_ type: Int32) throws -> (Int32, UInt16) {
        let fd=socket(AF_INET,type,0);guard fd>=0 else {throw Failure.socketUnavailable}
        var addr=sockaddr_in();addr.sin_len=UInt8(MemoryLayout<sockaddr_in>.size);addr.sin_family=sa_family_t(AF_INET);addr.sin_addr.s_addr=inet_addr("127.0.0.1")
        let bound=withUnsafePointer(to:&addr){$0.withMemoryRebound(to:sockaddr.self,capacity:1){ Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))}}
        var length=socklen_t(MemoryLayout<sockaddr_in>.size)
        let named=withUnsafeMutablePointer(to:&addr){$0.withMemoryRebound(to:sockaddr.self,capacity:1){getsockname(fd,$0,&length)}}
        guard bound==0,named==0,addr.sin_port != 0 else {close(fd);throw Failure.socketUnavailable}
        return (fd,UInt16(bigEndian:addr.sin_port))
    }
    static func main() throws {
        try require(try !state())
        let (peer,port)=try localSocket(SOCK_DGRAM);defer {close(peer)}
        let (reserve,socks)=try localSocket(SOCK_STREAM);close(reserve)
        let a=Curve25519.KeyAgreement.PrivateKey(),b=Curve25519.KeyAgreement.PrivateKey()
        let profile="[Interface]\nPrivateKey=\(a.rawRepresentation.base64EncodedString())\nAddress=10.77.0.2/32, 2001:db8:77::2/128\nDNS=192.0.2.53\nMTU=1280\n[Peer]\nPublicKey=\(b.publicKey.rawRepresentation.base64EncodedString())\nAllowedIPs=0.0.0.0/0, ::/0\nEndpoint=127.0.0.1:\(port)"
        let wg=try NativeWireGuardRuntimeConfig.compile(profile,expected:.wireGuard,socksPort:Int(socks))
        let good=wg.withEngineConfiguration{$0}
        try require(try call("testXray",config:good)["success"] as? Bool == true)
        try require(try call("testXray",config:Data("{".utf8))["success"] as? Bool == false)
        try require(try !state())
        for _ in 0..<3 {
            defer { _ = try? call("stopXray") }
            try require(try call("runXray",config:good)["success"] as? Bool == true)
            try require(try state())
            try require(try call("stopXray")["success"] as? Bool == true)
            try require(try !state())
        }
        print("XRAY_LOOPBACK_WG_CONFIG_NEGATIVE_AND_LIFECYCLE_3_OF_3_PASS")
    }
}
