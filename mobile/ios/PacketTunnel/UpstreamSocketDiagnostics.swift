import Darwin
import Foundation

/// Read-only count of this extension process's TCP sockets connected to the upstream.
/// Uses public Darwin APIs; no lsof, subprocesses, external network requests or secrets.
enum UpstreamSocketDiagnostics {
    static func sample(host: String, port: Int) -> ConnectionPressurePolicy.Sample {
        guard (1...65535).contains(port) else {
            return .init(upstreamSockets: 0, closeWaitSockets: 0)
        }
        var limits = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limits) == 0 else {
            return .init(upstreamSockets: 0, closeWaitSockets: 0)
        }
        let maxFD = max(0, Int(min(limits.rlim_cur, rlim_t(4096))))
        let numericHost = host.contains(":") ||
            (host.contains(".") && host.allSatisfy { $0.isNumber || $0 == "." })
        var count = 0
        var closeWait = 0

        for fd in 0..<maxFD {
            var address = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let result = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getpeername(Int32(fd), $0, &length)
                }
            }
            guard result == 0 else { continue }
            let remotePort: UInt16
            switch Int32(address.ss_family) {
            case AF_INET:
                remotePort = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        UInt16(bigEndian: $0.pointee.sin_port)
                    }
                }
            case AF_INET6:
                remotePort = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                        UInt16(bigEndian: $0.pointee.sin6_port)
                    }
                }
            default:
                continue
            }
            guard remotePort == port else { continue }
            if numericHost {
                var remoteHost = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let nameResult = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        getnameinfo($0, length, &remoteHost, socklen_t(remoteHost.count),
                                    nil, 0, NI_NUMERICHOST)
                    }
                }
                guard nameResult == 0,
                      String(cString: remoteHost).caseInsensitiveCompare(host) == .orderedSame else {
                    continue
                }
            }
            count += 1
            var info = tcp_connection_info()
            var infoLength = socklen_t(MemoryLayout<tcp_connection_info>.size)
            let hasState = getsockopt(Int32(fd), IPPROTO_TCP, TCP_CONNECTION_INFO, &info, &infoLength)
            // Darwin TCP state 5 = TCPS_CLOSE_WAIT.
            if hasState == 0 && info.tcpi_state == 5 {
                closeWait += 1
            }
        }
        return .init(upstreamSockets: count, closeWaitSockets: closeWait)
    }
}
