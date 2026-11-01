import Darwin
import Foundation

private final class AcceptedStore: @unchecked Sendable {
    let lock = NSLock()
    var sockets: [Int32] = []
    var running = true
    func append(_ fd: Int32) {
        lock.lock(); sockets.append(fd); lock.unlock()
    }
    func closeAll() {
        lock.lock()
        running = false
        for fd in sockets { Darwin.close(fd) }
        sockets.removeAll()
        lock.unlock()
    }
}

@main
struct TLSRelayIntegration {
    static func main() async throws {
        let server = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        precondition(server >= 0)
        defer { Darwin.close(server) }
        var upstream = sockaddr_in()
        upstream.sin_family = sa_family_t(AF_INET)
        upstream.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        var socklen = socklen_t(MemoryLayout<sockaddr_in>.size)
        precondition(withUnsafePointer(to: &upstream) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(server, $0, socklen)
            }
        } == 0)
        precondition(Darwin.listen(server, 120) == 0)
        precondition(withUnsafeMutablePointer(to: &upstream) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(server, $0, &socklen)
            }
        } == 0)
        let upstreamPort = Int(UInt16(bigEndian: upstream.sin_port))
        let accepted = AcceptedStore()
        DispatchQueue.global(qos: .utility).async {
            while accepted.running {
                let fd = Darwin.accept(server, nil, nil)
                if fd >= 0 { accepted.append(fd) }
                else { break }
            }
        }
        // Same production relay, accelerated policy only for this test:
        // 6-second idle TTL and 1-second sweep avoid a 107-second wait.
        let relay = TLSProxyRelay(
            host: "127.0.0.1",
            port: upstreamPort,
            policy: RelayConnectionPolicy(maximumIdleSeconds: 6),
            sweepIntervalSeconds: 1
        )
        let relayPort = try await relay.start()
        var relayAddress = upstream
        relayAddress.sin_port = UInt16(relayPort).bigEndian
        var clients: [Int32] = []
        for _ in 0..<105 {
            let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            if fd < 0 { continue }
            let status = withUnsafePointer(to: &relayAddress) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen)
                }
            }
            if status == 0 { clients.append(fd) }
            else { Darwin.close(fd) }
        }
        print("Local test clients connected: \(clients.count)")
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let before = UpstreamSocketDiagnostics.sample(host: "127.0.0.1", port: upstreamPort)
        print("Before TTL: \(before.upstreamSockets) upstream TCP, \(before.closeWaitSockets) CLOSE_WAIT")
        precondition(before.upstreamSockets > 0, "No upstream TLS handshakes created")
        precondition(before.upstreamSockets <= 90, "Relay pair ceiling not enforced")
        // The upstream accepts TCP but never completes TLS handshake. No data
        // can update lastActivityAt; the accelerated sweeper must release pairs.
        try await Task.sleep(nanoseconds: 8_000_000_000)
        let after = UpstreamSocketDiagnostics.sample(host: "127.0.0.1", port: upstreamPort)
        print("After TTL: \(after.upstreamSockets) upstream TCP, \(after.closeWaitSockets) CLOSE_WAIT")
        precondition(after.upstreamSockets == 0, "Relay did not reap stale TLS handshakes")
        relay.stop()
        for fd in clients { Darwin.close(fd) }
        accepted.closeAll()
        print("PASS: live TLS relay pair ceiling and stale handshake cleanup")
    }
}
