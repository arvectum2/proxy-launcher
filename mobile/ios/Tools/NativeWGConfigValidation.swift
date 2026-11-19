// Standalone compiler acceptance only. No connections or engine start.
import Foundation
import CryptoKit
import LibXray

@main struct NativeWGConfigValidation {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(1) }
        let local = Curve25519.KeyAgreement.PrivateKey().rawRepresentation.base64EncodedString()
        let peer = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let profile = """
        [Interface]
        PrivateKey = \(local)
        Address = 10.77.0.2/32, 2001:db8:77::2/128
        DNS = 192.0.2.53
        MTU = 1280
        [Peer]
        PublicKey = \(peer)
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = 127.0.0.1:39891
        PersistentKeepalive = 25
        """
        let wg = try NativeWireGuardRuntimeConfig.compile(profile, expected:.wireGuard)
        let request = try wg.withEngineConfiguration { config in
            try JSONSerialization.data(withJSONObject:["apiVersion":3,"method":"testXray","payload":["xrayJson":String(decoding:config,as:UTF8.self)]])
        }
        guard let input = strdup(String(decoding:request,as:UTF8.self)) else {exit(2)}
        defer {free(input)}
        guard let reply = CGoInvoke(input) else {exit(3)}
        defer {CGoFree(reply)}
        let count = strnlen(reply,65537)
        guard count <= 65536, let parsed = try JSONSerialization.jsonObject(with:Data(bytes:reply,count:count)) as? [String:Any], parsed["success"] as? Bool == true else { print("XRAY_CONFIG_REJECTED");exit(4) }
        print("PINNED_XRAY_WG_CONFIG_ACCEPTED")
        let awgText = profile.replacingOccurrences(of:"[Peer]",with:"Jc = 0\nJmin = 0\nJmax = 0\nS1 = 15\nS2 = 18\nH1 = 123456\nH2 = 67543\nH3 = 123123\nH4 = 32345\n[Peer]")
        let awg = try NativeWireGuardRuntimeConfig.compile(awgText, expected:.amneziaWG1)
        try awg.withEngineConfiguration { try $0.write(to:URL(fileURLWithPath:CommandLine.arguments[1]),options:.atomic) }
    }
}
