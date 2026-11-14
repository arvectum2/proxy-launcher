// Synthetic IP/TCP/UDP peer on a private datagram socketpair, not a system utun.
#if APL_TUN_PAIR_QA && targetEnvironment(simulator)
import Darwin
import Foundation
import tun2proxy

enum XrayTunPacketQA {
    private static let source: [UInt8] = [10, 77, 0, 2]
    private static let destination: [UInt8] = [198, 51, 100, 77]
    private static let source6: [UInt8] = [0x20,1,0x0d,0xb8,0,0x77,0,0,0,0,0,0,0,0,0,2]
    private static let destination6: [UInt8] = [0x20,1,0x0d,0xb8,0,0x77,0,0,0,0,0,0,0,0,0,0x77]
    private static let sourcePort: UInt16 = 45217
    private static let destinationPort: UInt16 = 39883
    private static func word(_ n: UInt16) -> [UInt8] {
        [UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)]
    }
    private static func long(_ n: UInt32) -> [UInt8] {
        word(UInt16(truncatingIfNeeded: n >> 16)) + word(UInt16(truncatingIfNeeded: n))
    }
    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) << 8 | UInt16(b[i+1])
    }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(u16(b,i)) << 16 | UInt32(u16(b,i+2))
    }
    private static func checksum(_ b: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        for i in stride(from: 0, to: b.count, by: 2) {
            sum += UInt32(b[i]) << 8
            if i + 1 < b.count { sum += UInt32(b[i+1]) }
        }
        while sum > 65535 { sum = (sum & 65535) + (sum >> 16) }
        return ~UInt16(sum)
    }
    private static func addresses(_ v6: Bool) -> ([UInt8],[UInt8]) {
        v6 ? (source6,destination6) : (source,destination)
    }
    private static func pseudo(_ count:Int, _ proto:UInt8, _ v6:Bool) -> [UInt8] {
        let (a,b) = addresses(v6)
        if v6 { return a + b + long(UInt32(count)) + [0,0,0,proto] }
        return a + b + [0,proto] + word(UInt16(count))
    }
    private static func sendIP(_ fd:Int32, _ body:[UInt8], _ proto:UInt8, _ v6:Bool) -> Bool {
        let (a,b) = addresses(v6)
        var ip:[UInt8]
        if v6 {
            ip = [0x60,0,0,0] + word(UInt16(body.count)) + [proto,64] + a + b
        } else {
            ip = [0x45,0] + word(UInt16(20+body.count)) + [0,1,0x40,0,64,proto,0,0] + a + b
            let sum=word(checksum(ip)); ip[10]=sum[0];ip[11]=sum[1]
        }
        let packet = [UInt8(0),0,0,UInt8(v6 ? AF_INET6 : AF_INET)] + ip + body
        return packet.withUnsafeBytes { send(fd,$0.baseAddress,$0.count,0) == $0.count }
    }
    private static func sendPacket(_ fd:Int32, seq:UInt32, ack:UInt32,
                                   flags:UInt8, payload:[UInt8]=[], v6:Bool=false) -> Bool {
        var tcp=word(sourcePort)+word(destinationPort)
        tcp += long(seq)+long(ack)
        tcp += [0x50,flags,0xff,0xff,0,0,0,0]+payload
        let sum=word(checksum(pseudo(tcp.count,6,v6)+tcp))
        tcp[16]=sum[0];tcp[17]=sum[1]
        return sendIP(fd,tcp,6,v6)
    }
    // Only exact synthetic connection; no acceptance of unexpected fragments/extensions.
    private static func receiveIP(_ fd:Int32,_ proto:UInt8,_ v6:Bool)->[UInt8]? {
        var bytes=[UInt8](repeating:0,count:2048)
        let n=bytes.withUnsafeMutableBytes { recv(fd,$0.baseAddress,$0.count,0) }
        let header=v6 ? 40 : 20
        guard n>=4+header+8 else{return nil}
        let b=Array(bytes.prefix(n))
        let (a,d)=addresses(v6)
        guard b[0...2].allSatisfy({$0==0}), b[3]==UInt8(v6 ? AF_INET6 : AF_INET) else{return nil}
        if v6 {
            guard b[4]>>4==6,b[10]==proto,Int(u16(b,8))==n-44,
                  Array(b[12..<28])==d,Array(b[28..<44])==a else{return nil}
        } else {
            guard b[4]==0x45,b[13]==proto,Int(u16(b,6))==n-4,
                  Array(b[16..<20])==d,Array(b[20..<24])==a else{return nil}
        }
        let t=Array(b[(4+header)...])
        guard u16(t,0)==destinationPort,u16(t,2)==sourcePort else{return nil}
        return t
    }
    private static func receive(_ fd:Int32,_ v6:Bool)->(UInt32,UInt32,UInt8,[UInt8])? {
        guard let t=receiveIP(fd,6,v6),t.count>=20 else{return nil}
        let offset=Int(t[12]>>4)*4
        guard offset>=20,offset<=t.count else{return nil}
        return (u32(t,4),u32(t,8),t[13],Array(t[offset...]))
    }
    static func probeUDP(fd:Int32,path:String,v6:Bool)->Bool {
        guard path.count==41,path.first=="/",path.dropFirst().allSatisfy({$0.isHexDigit}) else{return false}
        var timeout=timeval(tv_sec:0,tv_usec:250000)
        setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
        let body=Array(("APL_UDP:"+path.dropFirst()).utf8)
        var udp=word(sourcePort)+word(destinationPort)+word(UInt16(8+body.count))+[0,0]+body
        let check=checksum(pseudo(udp.count,17,v6)+udp)
        let sum=word(check == 0 ? 0xffff : check)
        udp[6]=sum[0];udp[7]=sum[1]
        guard sendIP(fd,udp,17,v6) else{return false}
        print("TUN_QA_UDP_INJECTED_"+(v6 ? "6" : "4"))
        let until=DispatchTime.now() + .seconds(6)
        while DispatchTime.now()<until {
            guard let t=receiveIP(fd,17,v6),Int(u16(t,4))==t.count else{continue}
            if Array(t.dropFirst(8))==Array(("APL_RECEIPT:"+path.dropFirst()).utf8){return true}
        }
        return false
    }
    static func probe(fd: Int32, path: String, v6:Bool = false) -> Bool {
        guard path.count == 41, path.first == "/",
              path.dropFirst().allSatisfy({ $0.isHexDigit }) else { return false }
        var timeout = timeval(tv_sec: 0,tv_usec: 250000)
        setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
        let initial: UInt32 = 12345678
        var seq = initial + 1, ack: UInt32 = 0
        guard sendPacket(fd,seq: initial,ack:0,flags:2,v6:v6) else { return false }
        let start = DispatchTime.now()
        let deadline = start + .seconds(6)
        var established = false
        while DispatchTime.now() < deadline {
            if let p = receive(fd,v6), p.2 & 0x12 == 0x12, p.1 == seq {
                ack = p.0 &+ 1; established = true; break
            }
        }
        guard established else { print("TUN_QA_NO_SYNACK"); return false }
        print("TUN_QA_SYNACK")
        let request = Array("GET \(path) HTTP/1.1\r\nHost: apl-receipt.invalid\r\nConnection: close\r\n\r\n".utf8)
        guard sendPacket(fd,seq:seq,ack:ack,flags:0x10,v6:v6),
              sendPacket(fd,seq:seq,ack:ack,flags:0x18,payload:request,v6:v6) else { return false }
        seq += UInt32(request.count)
        var result = [UInt8]()
        while DispatchTime.now() < deadline {
            guard let p = receive(fd,v6) else { continue }
            if p.2 & 4 != 0 { break }
            if p.0 == ack {
                result += p.3
                ack = ack &+ UInt32(p.3.count) &+ (p.2 & 1 == 1 ? 1 : 0)
            }
            if !p.3.isEmpty || p.2 & 1 != 0 {
                _ = sendPacket(fd,seq:seq,ack:ack,flags:0x10,v6:v6)
            }
            if result.count > 4096 { return false }
            if let response = String(bytes:result,encoding:.utf8),
               let boundary = response.range(of:"\r\n\r\n"),
               response.hasPrefix("HTTP/1.0 200"),
               String(response[boundary.upperBound...]) == "APL_RECEIPT:" + path.dropFirst() {
                _ = sendPacket(fd,seq:seq,ack:ack,flags:0x11,v6:v6)
                return true
            }
            if p.2 & 1 != 0 { break }
        }
        return false
    }
}
#endif
