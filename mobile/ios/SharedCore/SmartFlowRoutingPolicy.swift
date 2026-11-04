import Foundation

/// Pure policy prototype for a future domain-aware tun2proxy flow router.
/// Not wired to PacketTunnelProvider: excludedRoutes cannot safely enforce
/// exact-host decisions on an IP shared by different CDN hostnames.
enum SmartFlowDisposition: Equatable {
    case proxy
    case direct
}

/// Stable Smart Routing 4.0 reasons contain no host, IP, URL or credentials.
enum SmartRouteReason: String, Codable, Equatable {
    case manualExclusion = "MANUAL"
    case approvedDependency = "APPROVED"
    case noMatchingPermission = "NO_RULE"
    case unverifiedHost = "UNVERIFIED_HOST"
}

struct SmartRouteEvaluation: Equatable {
    let disposition: SmartFlowDisposition
    let reason: SmartRouteReason
}

struct SmartFlowRoutingPolicy {
    private let manualHosts: Set<String>
    private let approvedDependencyHosts: Set<String>

    init(manual: [String], graph: SmartExclusionGraph, at now: Date = Date()) throws {
        let normalizedManual = try SiteExclusionPolicy.normalizeAll(manual)
        let effective = try graph.effective(manual: manual, at: now)
        // Preserve exactly the previously allowed direct DNS hosts. Partition
        // them by source without granting new permission or changing ordering.
        let explicit = normalizedManual.flatMap { SiteExclusionPolicy.routingHosts(for: $0) }
        let all = effective.flatMap { SiteExclusionPolicy.routingHosts(for: $0) }
        manualHosts = Set(explicit.filter { SiteDependencyDiscovery.isScannableHost($0) })
        approvedDependencyHosts = Set(all.filter {
            SiteDependencyDiscovery.isScannableHost($0)
        }).subtracting(manualHosts)
    }

    /// Explanations are read-only: only exact verified DNS names can be DIRECT.
    /// A resolved IP is never permission because unrelated names can share it.
    func explain(host: String?, resolvedIP: String?) -> SmartRouteEvaluation {
        guard let host = host?.lowercased(),
              let normalized = try? SiteExclusionPolicy.normalize(host),
              host == normalized,
              SiteDependencyDiscovery.isScannableHost(host) else {
            return .init(disposition: .proxy, reason: .unverifiedHost)
        }
        _ = resolvedIP
        if manualHosts.contains(host) {
            return .init(disposition: .direct, reason: .manualExclusion)
        }
        if approvedDependencyHosts.contains(host) {
            return .init(disposition: .direct, reason: .approvedDependency)
        }
        return .init(disposition: .proxy, reason: .noMatchingPermission)
    }

    /// Historical API outcome is unchanged; do not write network routes here.
    func decide(host: String?, resolvedIP: String?) -> SmartFlowDisposition {
        explain(host: host, resolvedIP: resolvedIP).disposition
    }
}
