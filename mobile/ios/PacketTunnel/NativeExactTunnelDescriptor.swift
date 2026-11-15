#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_PRODUCT_RUNTIME_REVIEW
import Darwin
import Foundation

/// Never guess the first utun. Reject preexisting address collisions and
/// require a unique socket descriptor matching the exact new interface.
enum NativeExactTunnelDescriptor {
    static func interfaces(address target:String)->Set<String>? {
        var head:UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head)==0,let head else{return nil}
        defer{freeifaddrs(head)}
        var cursor:UnsafeMutablePointer<ifaddrs>?=head,names=Set<String>()
        while let entry=cursor?.pointee{
            cursor=entry.ifa_next
            guard let address=entry.ifa_addr,address.pointee.sa_family==UInt8(AF_INET) else{continue}
            var value=[CChar](repeating:0,count:Int(NI_MAXHOST))
            if getnameinfo(address,socklen_t(MemoryLayout<sockaddr_in>.size),&value,socklen_t(value.count),nil,0,NI_NUMERICHOST)==0,String(cString:value)==target {names.insert(String(cString:entry.ifa_name))}
        }
        return names
    }
    static func find(address:String)->Int32? {
        guard let names=interfaces(address:address),names.count==1,let name=names.first,name.hasPrefix("utun"),Int(name.dropFirst(4)) != nil else{return nil}
        var candidates=[Int32]()
        for fd in 0..<Int32(min(getdtablesize(),4096)){
            var buffer=[CChar](repeating:0,count:Int(IFNAMSIZ)),length=socklen_t(IFNAMSIZ)
            if buffer.withUnsafeMutableBytes({getsockopt(fd,2,2,$0.baseAddress,&length)})==0,length>0,length<=socklen_t(buffer.count),buffer.contains(0),String(cString:buffer)==name {candidates.append(fd)}
        }
        guard candidates.count==1,interfaces(address:address)==names else{return nil}
        return candidates[0]
    }
}
#endif
