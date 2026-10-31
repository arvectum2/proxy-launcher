import Darwin
import Foundation

/// Standalone public-API smoke test for UpstreamSocketDiagnostics.
/// Compile this file together with ConnectionPressurePolicy and the sampler.
@main
struct SocketDiagnosticsSmoke {
    static func main() throws {
        let server = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        precondition(server >= 0)
        defer { Darwin.close(server) }

        var bindAddress = sockaddr_in()
        bindAddress.sin_family = sa_family_t(AF_INET)
        bindAddress.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &bindAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(server, $0, addressLength)
            }
        }
        precondition(bound == 0)
        precondition(Darwin.listen(server, 2) == 0)
        let gotAddress = withUnsafeMutablePointer(to: &bindAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(server, $0, &addressLength)
            }
        }
        precondition(gotAddress == 0)
        let port = Int(UInt16(bigEndian: bindAddress.sin_port))
        let client = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        precondition(client >= 0)
        var connectAddress = bindAddress
        let connected = withUnsafePointer(to: &connectAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(client, $0, addressLength)
            }
        }
        precondition(connected == 0)
        let accepted = Darwin.accept(server, nil, nil)
        precondition(accepted >= 0)
        Darwin.close(accepted) // The local client should transition to CLOSE_WAIT.
        usleep(180_000)
        let before = UpstreamSocketDiagnostics.sample(host: "127.0.0.1", port: port)
        precondition(before.upstreamSockets >= 1, "Connected socket not counted")
        precondition(before.closeWaitSockets >= 1, "CLOSE_WAIT socket not counted")
        let unrelated = UpstreamSocketDiagnostics.sample(host: "192.0.2.30", port: port)
        precondition(unrelated.upstreamSockets == 0, "Unrelated host counted")
        Darwin.close(client)
        usleep(80_000)
        let after = UpstreamSocketDiagnostics.sample(host: "127.0.0.1", port: port)
        precondition(after.upstreamSockets == 0, "Closed socket still counted")
        print("PASS: socket peer filter, CLOSE_WAIT detection, closure and cleanup")
    }
}
