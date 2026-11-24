// QA only: one connected UDP socket and one fixed nonce datagram.
import Darwin
import Foundation

enum FixedUDPWitness {
    static func matches(_ response:Data,nonce:String)->Bool {
        ScopedTCPWitness.validNonce(nonce) && response==Data(("APL_RECEIPT:"+nonce).utf8)
    }
    static func run(_ nonce:String,kind:FixedWitnessKind)->ScopedTCPWitness.Result {
        var result=ScopedTCPWitness.Result()
        guard kind.udp,ScopedTCPWitness.validNonce(nonce) else{return result}
        result.counters["hostUDPAttempted"]=1
        let fd=Darwin.socket(kind.family,SOCK_DGRAM,0)
        guard fd>=0 else{result.counters["hostSocketErrno"]=Int(errno);return result}
        defer{Darwin.close(fd)}
        let flags=fcntl(fd,F_GETFL)
        guard flags>=0,fcntl(fd,F_SETFL,flags|O_NONBLOCK)==0 else{result.counters["hostSocketErrno"]=Int(errno);return result}
        guard kind.connect(fd)==0 else{result.counters["hostConnectErrno"]=Int(errno);return result}
        result.counters["hostUDPSocketAssociated"]=1
        let deadline=DispatchTime.now().uptimeNanoseconds+6_000_000_000
        func ready(_ events:Int16)->Bool {
            while true {
                let now=DispatchTime.now().uptimeNanoseconds
                guard now<deadline else{errno=ETIMEDOUT;return false}
                var p=pollfd(fd:fd,events:events,revents:0)
                let n=Darwin.poll(&p,1,Int32(min((deadline-now+999_999)/1_000_000,6000)))
                if n>0{return true}
                if n==0{errno=ETIMEDOUT;return false}
                if errno != EINTR{return false}
            }
        }
        let request=Array(("APL_UDP:"+nonce).utf8)
        guard ready(Int16(POLLOUT)) else{result.counters["hostSendErrno"]=Int(errno);return result}
        let sent=request.withUnsafeBytes{Darwin.send(fd,$0.baseAddress!,request.count,0)}
        guard sent==request.count else{result.counters["hostSendErrno"]=Int(errno);return result}
        result.counters["hostSentBytes"]=sent
        result.counters["hostDatagramsSent"]=1
        guard ready(Int16(POLLIN)) else{result.counters["hostReceiveErrno"]=Int(errno);return result}
        var bytes=[UInt8](repeating:0,count:256)
        let got=bytes.withUnsafeMutableBytes{Darwin.recv(fd,$0.baseAddress!,$0.count,0)}
        guard got>0 else{result.counters["hostReceiveErrno"]=Int(errno);return result}
        result.counters["hostReceivedBytes"]=got
        result.counters["hostDatagramsReceived"]=1
        result.exact=matches(Data(bytes.prefix(got)),nonce:nonce)
        return result
    }
}
