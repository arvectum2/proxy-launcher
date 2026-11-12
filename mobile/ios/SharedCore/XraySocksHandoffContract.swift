import Darwin
import Foundation

/// Future, currently inactive PacketTunnel-to-Xray local SOCKS handoff.
/// No credentials, persisted profiles, NetworkExtension mutations or DIRECT.
enum XrayHandoffError: Error, Equatable {
    case invalidDescriptor, invalidPort, invalidBypass, tooManyBypasses
    case invalidTransition, staleCallback, exhaustedGeneration
}

struct XraySocksHandoffPlan: Equatable {
    let port: UInt16
    let tunnelDescriptor: Int32
    let dnsBypasses: [String]
    let proxyURL: String
    let tun2proxyArguments: String

    static func prepare(tunFD: Int, socksPort: Int, dnsBypass: [String]) throws -> Self {
        guard (0...Int(Int32.max)).contains(tunFD) else {
            throw XrayHandoffError.invalidDescriptor
        }
        guard (1024...65535).contains(socksPort) else {
            throw XrayHandoffError.invalidPort
        }
        guard dnsBypass.count <= 64 else { throw XrayHandoffError.tooManyBypasses }
        var unique = Set<String>()
        for raw in dnsBypass {
            guard raw == raw.lowercased(), validBypassHost(raw),
                  unique.insert(raw).inserted else {
                throw XrayHandoffError.invalidBypass
            }
        }
        let bypasses = unique.sorted()
        let url = "socks5://127.0.0.1:\(socksPort)"
        var args = "tun2proxy-bin --proxy \(url) --tun-fd \(tunFD)"
        args += " --close-fd-on-drop false --dns virtual --ipv6-enabled --verbosity warn"
        for host in bypasses { args += " --dns-bypass \(host)" }
        return .init(port: UInt16(socksPort), tunnelDescriptor: Int32(tunFD),
                     dnsBypasses: bypasses, proxyURL: url, tun2proxyArguments: args)
    }

    private static func validBypassHost(_ host: String) -> Bool {
        if ManagedProfileContract.validDNS(host) { return true }
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return host.withCString {
            inet_pton(AF_INET, $0, &ipv4) == 1 ||
            inet_pton(AF_INET6, $0, &ipv6) == 1
        }
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
