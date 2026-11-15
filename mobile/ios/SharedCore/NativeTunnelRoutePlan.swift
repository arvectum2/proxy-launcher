import Foundation
import Darwin

/// Offline candidate settings. No engine or NE activation here. In particular,
/// a remote endpoint is NOT an excluded route: that would bypass the tunnel
/// for unrelated application traffic to the same IP. The future provider
/// must establish and verify its own underlay path independently.
struct NativeTunnelRoutePlan: Equatable {
    enum Failure: Error, Equatable {
        case unsupportedProtocol, unsupportedPolicy, invalidAddress, conflictingAddress
    }
    enum UnderlayRequirement: Equatable { case providerOwnedSocketVerifiedBeforeActivation }
    let provider: TransportProvider
    let ipv4Address: String
    let ipv6Address: String
    let remoteAddress: String
    let remotePort: UInt16
    let dnsServers: [String]
    let mtu: Int
    let underlay: UnderlayRequirement = .providerOwnedSocketVerifiedBeforeActivation
    var ipv4DefaultRoutes: [String] { ["0.0.0.0/0"] }
    var ipv6DefaultRoutes: [String] { ["::/1", "8000::/1"] }
    var excludedRoutes: [String] { [] }
    var dnsMatchDomains: [String] { [""] }

    static func prepare(_ config: NativeWireGuardRuntimeConfig,
                        routes: TransportBackendPlan.RoutePolicy = .tunnelOnly,
                        siteExclusions: [String] = [], applicationExclusions: [String] = []) throws -> Self {
        guard routes == .tunnelOnly, siteExclusions.isEmpty, applicationExclusions.isEmpty else {
            throw Failure.unsupportedPolicy
        }
        guard (config.wireProtocol == .wireGuard && config.provider == .rustXray) ||
              (config.wireProtocol == .amneziaWG1 && config.provider == .standaloneAWG) else {
            throw Failure.unsupportedProtocol
        }
        let addresses = try config.addresses.map { item -> IP in
            let parts = item.split(separator:"/",omittingEmptySubsequences:false)
            guard parts.count == 2, let ip = IP(String(parts[0])),
                  parts[1] == (ip.v6 ? "128" : "32") else { throw Failure.invalidAddress }
            return ip
        }
        guard addresses.count == 2, let v4 = addresses.first(where:{!$0.v6}),
              let v6 = addresses.first(where:{$0.v6}) else { throw Failure.invalidAddress }
        let endpoint = config.remoteEndpoint
        let host: String, portText: String
        if endpoint.hasPrefix("["), let end = endpoint.firstIndex(of:"]"),
           endpoint.index(after:end) < endpoint.endIndex,
           endpoint[endpoint.index(after:end)] == ":" {
            host = String(endpoint[endpoint.index(after:endpoint.startIndex)..<end])
            portText = String(endpoint[endpoint.index(end,offsetBy:2)...])
        } else {
            let parts = endpoint.split(separator:":",omittingEmptySubsequences:false)
            guard parts.count == 2 else { throw Failure.invalidAddress }
            host = String(parts[0]); portText = String(parts[1])
        }
        guard let remote = IP(host), let port = UInt16(portText), port > 0 else { throw Failure.invalidAddress }
        let dns = try config.dnsServers.map { raw -> IP in
            guard let ip = IP(raw) else { throw Failure.invalidAddress }; return ip
        }
        guard !dns.isEmpty, Set(dns).count == dns.count else { throw Failure.invalidAddress }
        guard !addresses.contains(remote), !dns.contains(remote),
              Set(addresses).isDisjoint(with:Set(dns)) else { throw Failure.conflictingAddress }
        return .init(provider:config.provider, ipv4Address:v4.text, ipv6Address:v6.text,
                     remoteAddress:remote.text, remotePort:port, dnsServers:dns.map(\.text), mtu:config.mtu)
    }

    /// Accept literal unicast only. Private/ULA addresses are intentional;
    /// loopback, link-local, multicast, mapped IPv4 and unspecified are not.
    private struct IP: Hashable {
        let text: String
        let v6: Bool
        init?(_ raw: String) {
            var v4 = in_addr(), v6addr = in6_addr()
            if raw.withCString({inet_pton(AF_INET,$0,&v4)}) == 1 {
                let n = UInt32(bigEndian:v4.s_addr), first = n >> 24
                guard first != 0, first != 127, first < 224, n >> 16 != 0xa9fe else { return nil }
                var buf = [CChar](repeating:0,count:Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET,&v4,&buf,socklen_t(buf.count)) != nil else { return nil }
                text = String(cString:buf); v6 = false; return
            }
            guard raw.withCString({inet_pton(AF_INET6,$0,&v6addr)}) == 1 else { return nil }
            let b = withUnsafeBytes(of:&v6addr) { Array($0) }
            // Only global unicast (2000::/3) and ULA (fc00::/7), excluding
            // special IPv4-mapped/compatible and scoped addresses.
            guard b[0] & 0xe0 == 0x20 || b[0] & 0xfe == 0xfc else { return nil }
            var buf = [CChar](repeating:0,count:Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6,&v6addr,&buf,socklen_t(buf.count)) != nil else { return nil }
            text = String(cString:buf); v6 = true
        }
    }
}
