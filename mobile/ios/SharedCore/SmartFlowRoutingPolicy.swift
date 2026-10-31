import Foundation

/// Pure policy prototype for a future domain-aware tun2proxy flow router.
/// Not wired to PacketTunnelProvider: the existing IP-based excludedRoutes
/// cannot safely enforce exact-host decisions on a shared CDN address.
enum SmartFlowDisposition: Equatable {
    case proxy
    case direct
}

struct SmartFlowRoutingPolicy {
    private let permittedHosts: Set<String>

    init(manual: [String], graph: SmartExclusionGraph, at now: Date = Date()) throws {
        let effective = try graph.effective(manual: manual, at: now)
        // Do not use suffix/wildcards. Only exact DNS names, and approved
        // www aliases, can change this decision. Literal IPs cannot prove
        // which hostname caused the connection and do not qualify here.
        let all = effective.flatMap { SiteExclusionPolicy.routingHosts(for: $0) }
        permittedHosts = Set(all.filter { SiteDependencyDiscovery.isScannableHost($0) })
    }

    func decide(host: String?, resolvedIP: String?) -> SmartFlowDisposition {
        guard let host = host?.lowercased(),
              let normalized = try? SiteExclusionPolicy.normalize(host),
              host == normalized,
              SiteDependencyDiscovery.isScannableHost(host),
              permittedHosts.contains(host) else { return .proxy }
        // The IP is intentionally not a permission key. Different hostnames
        // can share this address and must remain on different paths.
        _ = resolvedIP
        return .direct
    }
}
