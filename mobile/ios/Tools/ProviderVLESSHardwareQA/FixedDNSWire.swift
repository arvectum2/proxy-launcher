// Synthetic DNS wire test only: never query a real resolver or user hostname.
import Foundation

enum FixedDNSWire {
    static func query(_ nonce:String)->Data {
        guard ScopedTCPWitness.validNonce(nonce) else{return Data()}
        var b:[UInt8]=[0xa1,0x17,0x01,0x00,0,1,0,0,0,0,0,0]
        for label in [nonce,"apl","invalid"] {
            b.append(UInt8(label.utf8.count));b.append(contentsOf:label.utf8)
        }
        b += [0,0,1,0,1]
        return Data(b)
    }
    static func expected(_ nonce:String)->Data {
        let q=query(nonce)
        guard !q.isEmpty else{return Data()}
        var b:[UInt8]=[0xa1,0x17,0x81,0x80,0,1,0,1,0,0,0,0]
        b.append(contentsOf:q.dropFirst(12))
        b += [0xc0,0x0c,0,1,0,1,0,0,0,0,0,4,192,0,2,53]
        return Data(b)
    }
    static func matches(_ response:Data,nonce:String)->Bool {
        let exact=expected(nonce)
        return !exact.isEmpty && response==exact
    }
}
