// QA only: never accept arbitrary destinations, ports or protocols.
import Foundation
import Darwin

enum FixedWitnessKind:String,CaseIterable,Sendable {
    case tcp4,tcp6,udp4,udp6,dnsWire4
    var v6:Bool {self == .tcp6 || self == .udp6}
    var udp:Bool {self == .udp4 || self == .udp6 || self == .dnsWire4}
    var ip:String {v6 ? "2001:db8:77::77":"198.51.100.77"}
    var cidr:String {ip+(v6 ? "/128":"/32")}
    var port:UInt16 {self == .dnsWire4 ? 53:39883}
    var network:String {udp ? "udp":"tcp"}
    var family:Int32 {v6 ? AF_INET6:AF_INET}
    func connect(_ fd:Int32)->Int32 {
        if v6 {
            var addr=sockaddr_in6()
            addr.sin6_len=UInt8(MemoryLayout<sockaddr_in6>.size)
            addr.sin6_family=sa_family_t(AF_INET6);addr.sin6_port=port.bigEndian
            guard ip.withCString({inet_pton(AF_INET6,$0,&addr.sin6_addr)})==1 else{return -1}
            return withUnsafePointer(to:&addr){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in6>.size))}}
        }
        var addr=sockaddr_in()
        addr.sin_len=UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family=sa_family_t(AF_INET);addr.sin_port=port.bigEndian
        guard ip.withCString({inet_pton(AF_INET,$0,&addr.sin_addr)})==1 else{return -1}
        return withUnsafePointer(to:&addr){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))}}
    }
}
