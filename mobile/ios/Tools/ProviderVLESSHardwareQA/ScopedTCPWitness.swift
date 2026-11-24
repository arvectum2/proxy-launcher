// QA-only fixed RFC5737 endpoint. No ATS changes, interface binding,
// credentials, persisted state, or production target.
import Darwin
import Foundation

enum ScopedTCPWitness {
    struct Result: Sendable {
        var exact=false
        var counters:[String:Int]=[:]
    }
    static func validNonce(_ nonce:String)->Bool {
        nonce.utf8.count==40 && nonce.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}
    }
    static func matches(_ response:Data,nonce:String)->Bool {
        guard validNonce(nonce),response.count<=8192,
              let split=response.range(of:Data([13,10,13,10])),
              let header=String(data:response[..<split.lowerBound],encoding:.ascii) else{return false}
        let lines=header.components(separatedBy:"\r\n")
        guard let first=lines.first,
              first.hasPrefix("HTTP/1.0 200 ") || first.hasPrefix("HTTP/1.1 200 ") else{return false}
        let lengths=lines.dropFirst().filter{$0.lowercased().hasPrefix("content-length:")}
        let body=Data(("APL_RECEIPT:"+nonce).utf8)
        guard lengths.count==1,
              Int(lengths[0].dropFirst("content-length:".count).trimmingCharacters(in:.whitespaces))==body.count,
              !lines.dropFirst().contains(where:{$0.lowercased().hasPrefix("transfer-encoding:")}) else{return false}
        return response[split.upperBound...]==body
    }
    static func run(_ nonce:String)->Result {
        var result=Result()
        guard validNonce(nonce) else{return result}
        result.counters["hostHTTPAttempted"]=1
        result.counters["hostRawTCP"]=1
        let fd=Darwin.socket(AF_INET,SOCK_STREAM,0)
        guard fd>=0 else{result.counters["hostSocketErrno"]=Int(errno);return result}
        defer{Darwin.close(fd)}
        let flags=fcntl(fd,F_GETFL)
        guard flags>=0,fcntl(fd,F_SETFL,flags|O_NONBLOCK)==0 else{result.counters["hostSocketErrno"]=Int(errno);return result}
        var one:Int32=1
        guard withUnsafePointer(to:&one,{setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,$0,socklen_t(MemoryLayout<Int32>.size))})==0 else{return result}
        let deadline=DispatchTime.now().uptimeNanoseconds+6_000_000_000
        func ready(_ events:Int16)->Bool {
            while true {
                let now=DispatchTime.now().uptimeNanoseconds
                guard now<deadline else{errno=ETIMEDOUT;return false}
                let remaining=Int32(min((deadline-now+999_999)/1_000_000,6000))
                var p=pollfd(fd:fd,events:events,revents:0)
                let n=Darwin.poll(&p,1,remaining)
                if n>0{return true}
                if n==0{errno=ETIMEDOUT;return false}
                if errno != EINTR{return false}
            }
        }
        var addr=sockaddr_in()
        addr.sin_len=UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family=sa_family_t(AF_INET);addr.sin_port=UInt16(39883).bigEndian
        guard "198.51.100.77".withCString({inet_pton(AF_INET,$0,&addr.sin_addr)})==1 else{return result}
        let rc=withUnsafePointer(to:&addr){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))}}
        if rc != 0 {
            guard errno==EINPROGRESS,ready(Int16(POLLOUT)) else{result.counters["hostConnectErrno"]=Int(errno);return result}
            var err:Int32=0,len=socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd,SOL_SOCKET,SO_ERROR,&err,&len)==0,err==0 else{result.counters["hostConnectErrno"]=Int(err==0 ? errno:err);return result}
        }
        result.counters["hostTCPConnected"]=1
        let request=Array("GET /\(nonce) HTTP/1.1\r\nHost: 198.51.100.77\r\nConnection: close\r\n\r\n".utf8)
        var offset=0
        while offset<request.count {
            guard ready(Int16(POLLOUT)) else{result.counters["hostSendErrno"]=Int(errno);return result}
            let n=request.withUnsafeBytes{Darwin.send(fd,$0.baseAddress!.advanced(by:offset),request.count-offset,0)}
            if n<0 && (errno==EINTR || errno==EAGAIN || errno==EWOULDBLOCK){continue}
            guard n>0 else{result.counters["hostSendErrno"]=Int(errno);return result}
            offset+=n
            result.counters["hostSentBytes"]=offset
        }
        var response=Data()
        while response.count<8192 {
            guard ready(Int16(POLLIN)) else{result.counters["hostReceiveErrno"]=Int(errno);return result}
            var buffer=[UInt8](repeating:0,count:min(2048,8192-response.count))
            let n=buffer.withUnsafeMutableBytes{Darwin.recv(fd,$0.baseAddress!,$0.count,0)}
            if n<0 && (errno==EINTR || errno==EAGAIN || errno==EWOULDBLOCK){continue}
            if n<0 {result.counters["hostReceiveErrno"]=Int(errno);return result}
            if n==0 {result.exact=matches(response,nonce:nonce);return result}
            response.append(contentsOf:buffer.prefix(n))
            result.counters["hostReceivedBytes"]=response.count
        }
        return result
    }
}
