// Match the lab interface by unique assigned address; never use a first-utun
// fallback. Same descriptor mechanism as existing APL, isolated here.
import Darwin
import Foundation

enum ExactLabTUNDescriptor {
    static func find(address target: String) -> Int32? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = addrs
        var names = Set<String>()
        while let p = cursor {
            cursor = p.pointee.ifa_next
            guard let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var value = [CChar](repeating:0,count:Int(NI_MAXHOST))
            if getnameinfo(addr,socklen_t(MemoryLayout<sockaddr_in>.size),&value,socklen_t(value.count),nil,0,NI_NUMERICHOST) == 0,
               String(cString:value) == target {
                names.insert(String(cString:p.pointee.ifa_name))
            }
        }
        guard names.count == 1, let name=names.first, name.hasPrefix("utun") else { return nil }
        var matches = [Int32]()
        for fd in 0..<Int32(min(getdtablesize(),4096)) {
            var value = [CChar](repeating:0,count:Int(IFNAMSIZ))
            var len = socklen_t(value.count)
            if value.withUnsafeMutableBytes({getsockopt(fd,2,2,$0.baseAddress,&len)}) == 0,
               len > 0, len <= socklen_t(value.count), value.contains(0),
               String(cString:value) == name { matches.append(fd) }
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
