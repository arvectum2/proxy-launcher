// Disposable local SOCKS association diagnostics: no application payload,
// no credential logging, no external destinations.
import Darwin
import Foundation

enum LabUDPAssociationDiagnostic {
    static func collect() -> [String:Int] {
        var out:[String:Int]=[:]
        func addr(_ host:UInt32,_ port:UInt16)->sockaddr_in {
            var a=sockaddr_in()
            a.sin_len=UInt8(MemoryLayout<sockaddr_in>.size)
            a.sin_family=sa_family_t(AF_INET)
            a.sin_addr=in_addr(s_addr:host.bigEndian)
            a.sin_port=port.bigEndian
            return a
        }
        func connectTo(_ fd:Int32,_ address:sockaddr_in)->Int32 {
            var a=address
            return withUnsafePointer(to:&a) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        }
        func bound(_ fd:Int32,_ address:sockaddr_in)->Int32 {
            var a=address
            return withUnsafePointer(to:&a) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        }
        let fd=socket(AF_INET,SOCK_STREAM,0)
        guard fd>=0 else{return ["diagnosticTCPSocketErrno":Int(errno)]}
        defer {close(fd)}
        var tv=timeval(tv_sec:1,tv_usec:0)
        _=setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv,socklen_t(MemoryLayout<timeval>.size))
        _=setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&tv,socklen_t(MemoryLayout<timeval>.size))
        guard connectTo(fd,addr(0x7f000001,39879))==0 else{return ["diagnosticTCPConnectErrno":Int(errno)]}
        func write(_ bytes:[UInt8])->Bool {
            bytes.withUnsafeBytes {Darwin.send(fd,$0.baseAddress,$0.count,0)==$0.count}
        }
        func read(_ count:Int)->[UInt8]? {
            var bytes=[UInt8](repeating:0,count:count)
            var offset=0
            while offset<count {
                let n=bytes.withUnsafeMutableBytes {Darwin.recv(fd,$0.baseAddress!.advanced(by:offset),count-offset,0)}
                if n<=0{return nil}
                offset+=n
            }
            return bytes
        }
        guard write([5,1,0]),read(2)==[5,0],
              write([5,3,0,1,0,0,0,0,0,0]),let head=read(4),head[0]==5,head[1]==0 else {
            return ["diagnosticAssociationFailed":1]
        }
        out["associationAddressType"]=Int(head[3])
        guard head[3]==1,let reply=read(6) else{return out}
        let host=reply.prefix(4).reduce(UInt32(0)) {($0<<8)|UInt32($1)}
        let port=(UInt16(reply[4])<<8)|UInt16(reply[5])
        out["associationLoopback"]=(host>>24)==127 ? 1:0
        out["associationUnspecified"]=host==0 ? 1:0
        guard (host>>24)==127,port>0 else{return out}
        for (name,source) in [("wildcard",UInt32(0)),("loopback",UInt32(0x7f000001))] {
            let udp=socket(AF_INET,SOCK_DGRAM,0)
            if udp<0{out[name+"SocketErrno"]=Int(errno);continue}
            defer{close(udp)}
            if bound(udp,addr(source,0)) != 0 {
                out[name+"BindErrno"]=Int(errno)
                continue
            }
            out[name+"ConnectErrno"]=connectTo(udp,addr(host,port))==0 ? 0:Int(errno)
        }
        return out
    }
}
