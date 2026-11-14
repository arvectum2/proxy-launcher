// Synthetic IPv4/TCP peer on a private datagram socketpair, not a system utun.
#if APL_TUN_PAIR_QA && targetEnvironment(simulator)
import Darwin
import Foundation
import tun2proxy

enum XrayTunPacketQA {
    private static let source: [UInt8] = [10, 77, 0, 2]
    private static let destination: [UInt8] = [198, 51, 100, 77]
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
    private static func sendPacket(_ fd: Int32, seq: UInt32, ack: UInt32,
                                   flags: UInt8, payload: [UInt8] = []) -> Bool {
        var tcp = word(sourcePort) + word(destinationPort)
        tcp += long(seq) + long(ack)
        tcp += [0x50, flags, 0xff, 0xff, 0, 0, 0, 0]
        tcp += payload
        let pseudo = source + destination + [0, 6] + word(UInt16(tcp.count))
        let tcpSum = word(checksum(pseudo + tcp))
        tcp[16] = tcpSum[0]; tcp[17] = tcpSum[1]
        var ip: [UInt8] = [0x45,0]
        ip += word(UInt16(20+tcp.count))
        ip += [0,1,0x40,0,64,6,0,0]
        ip += source + destination
        let ipSum = word(checksum(ip))
        ip[10] = ipSum[0]; ip[11] = ipSum[1]
        let packet = [UInt8(0),0,0,UInt8(AF_INET)] + ip + tcp
        return packet.withUnsafeBytes {
            send(fd,$0.baseAddress,$0.count,0) == $0.count
        }
    }
    // Accept only packets belonging to the exact synthetic connection.
    private static func receive(_ fd: Int32) -> (UInt32, UInt32, UInt8, [UInt8])? {
        var bytes = [UInt8](repeating: 0,count: 2048)
        let n = bytes.withUnsafeMutableBytes { recv(fd,$0.baseAddress,$0.count,0) }
        guard n >= 44 else { return nil }
        let b = Array(bytes.prefix(n))
        let ip = 4, tcp = ip + Int(b[ip] & 15) * 4
        guard b[3] == UInt8(AF_INET), b[ip] >> 4 == 4, b[ip+9] == 6,
              Array(b[(ip+12)..<(ip+16)]) == destination,
              Array(b[(ip+16)..<(ip+20)]) == source,
              tcp+20 <= b.count, u16(b,tcp) == destinationPort,
              u16(b,tcp+2) == sourcePort else { return nil }
        let data = tcp + Int(b[tcp+12] >> 4)*4
        guard data >= tcp+20, data <= b.count else { return nil }
        return (u32(b,tcp+4),u32(b,tcp+8),b[tcp+13],Array(b[data...]))
    }
    static func probe(fd: Int32, path: String) -> Bool {
        guard path.count == 41, path.first == "/",
              path.dropFirst().allSatisfy({ $0.isHexDigit }) else { return false }
        var timeout = timeval(tv_sec: 0,tv_usec: 250000)
        setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
        let initial: UInt32 = 12345678
        var seq = initial + 1, ack: UInt32 = 0
        guard sendPacket(fd,seq: initial,ack:0,flags:2) else { return false }
        let start = DispatchTime.now()
        let deadline = start + .seconds(6)
        var established = false
        while DispatchTime.now() < deadline {
            if let p = receive(fd), p.2 & 0x12 == 0x12, p.1 == seq {
                ack = p.0 &+ 1; established = true; break
            }
        }
        guard established else { print("TUN_QA_NO_SYNACK"); return false }
        print("TUN_QA_SYNACK")
        let request = Array("GET \(path) HTTP/1.1\r\nHost: apl-receipt.invalid\r\nConnection: close\r\n\r\n".utf8)
        guard sendPacket(fd,seq:seq,ack:ack,flags:0x10),
              sendPacket(fd,seq:seq,ack:ack,flags:0x18,payload:request) else { return false }
        seq += UInt32(request.count)
        var result = [UInt8]()
        while DispatchTime.now() < deadline {
            guard let p = receive(fd) else { continue }
            if p.2 & 4 != 0 { break }
            if p.0 == ack {
                result += p.3
                ack = ack &+ UInt32(p.3.count) &+ (p.2 & 1 == 1 ? 1 : 0)
            }
            if !p.3.isEmpty || p.2 & 1 != 0 {
                _ = sendPacket(fd,seq:seq,ack:ack,flags:0x10)
            }
            if result.count > 4096 { return false }
            if let response = String(bytes:result,encoding:.utf8),
               let boundary = response.range(of:"\r\n\r\n"),
               response.hasPrefix("HTTP/1.0 200"),
               String(response[boundary.upperBound...]) == "APL_RECEIPT:" + path.dropFirst() {
                _ = sendPacket(fd,seq:seq,ack:ack,flags:0x11)
                return true
            }
            if p.2 & 1 != 0 { break }
        }
        return false
    }
}
#endif
