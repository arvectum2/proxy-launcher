import Foundation

/// Future, currently inactive PacketTunnel-to-Xray local SOCKS handoff.
/// No credentials, persisted profiles, NetworkExtension mutations or DIRECT.
enum XrayHandoffError: Error, Equatable {
    case invalidDescriptor, invalidPort, unsupportedBypass
    case invalidTransition, staleCallback, exhaustedGeneration
}

struct XraySocksHandoffPlan: Equatable {
    let port: UInt16
    let tunnelDescriptor: Int32
    let dnsBypasses: [String]
    let proxyURL: String
    let tun2proxyArguments: String

    static func prepare(tunFD: Int, socksPort: Int, dnsBypass: [String],exactDNS:Bool=false) throws -> Self {
        guard (0...Int(Int32.max)).contains(tunFD) else {
            throw XrayHandoffError.invalidDescriptor
        }
        guard (1024...65535).contains(socksPort) else {
            throw XrayHandoffError.invalidPort
        }
        // The pinned native Rust artifact deliberately excludes the legacy
        // split-DNS/direct patches. A host-only flag was also incompatible
        // with the older HOST=IP parser. Do not silently drop user policy.
        guard dnsBypass.isEmpty else {throw XrayHandoffError.unsupportedBypass}
        guard !exactDNS || socksPort==39879 else{throw XrayHandoffError.invalidPort}
        let url = "socks5://127.0.0.1:\(socksPort)"
        let dnsMode=exactDNS ? " --dns direct --native-exact-dns":" --dns virtual"
        let args = "tun2proxy-bin --proxy \(url) --tun-fd \(tunFD)" +
            " --close-fd-on-drop false"+dnsMode+" --ipv6-enabled --verbosity warn"
        return .init(port:UInt16(socksPort),tunnelDescriptor:Int32(tunFD),dnsBypasses:[],proxyURL:url,tun2proxyArguments:args)
    }

}

/// Must be accessed only from the caller's single serial engine queue.
/// Generation tokens prevent stale callbacks and
/// a failed native engine cannot silently restart or take over the VPN.
struct XrayHandoffLifecycle: Equatable {
    enum Phase: Equatable { case idle, starting, running, stopping, stopped, failedClosed }
    private(set) var phase: Phase = .idle
    private(set) var generation: UInt64 = 0

    mutating func begin() throws -> UInt64 {
        guard phase == .idle || phase == .stopped else {
            throw XrayHandoffError.invalidTransition
        }
        guard generation < UInt64.max else {
            throw XrayHandoffError.exhaustedGeneration
        }
        generation += 1
        phase = .starting
        return generation
    }

    mutating func ready(generation token: UInt64) throws {
        guard token == generation else { throw XrayHandoffError.staleCallback }
        guard phase == .starting else { throw XrayHandoffError.invalidTransition }
        phase = .running
    }

    mutating func requestStop(generation token: UInt64) throws -> Bool {
        guard token == generation else { throw XrayHandoffError.staleCallback }
        switch phase {
        case .starting, .running:
            phase = .stopping
            return true
        case .stopping, .stopped, .idle, .failedClosed:
            return false
        }
    }

    mutating func drained(generation token: UInt64) throws {
        guard token == generation else { throw XrayHandoffError.staleCallback }
        guard phase == .stopping else { throw XrayHandoffError.invalidTransition }
        phase = .stopped
    }

    mutating func failClosed(generation token: UInt64) throws {
        guard token == generation else { throw XrayHandoffError.staleCallback }
        guard phase == .starting || phase == .running || phase == .stopping else {
            throw XrayHandoffError.invalidTransition
        }
        phase = .failedClosed
    }
}
