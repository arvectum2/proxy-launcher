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

/// Native candidate admission, not a flow router. Never silently discard a
/// stored bypass rule or downgrade normally-off routing to tunnel-only.
enum NativeRoutingAdmission:Equatable {
    case tunnelOnly, siteExclusions, dependencyPolicy, normallyOff, malformed
    var permitsSelection:Bool {self == .tunnelOnly}
    static func inspect(manual:Any?,legacy:Any?,graph:Any?,mode:Any?) -> Self {
        var hasEntries=false
        for value in [manual,legacy] {
            if let value {
                guard let list=value as? [String],list.count<=SiteExclusionPolicy.maxEntries,
                      list.allSatisfy({$0.utf8.count<=1024}), (try? SiteExclusionPolicy.normalizeAll(list)) != nil else{return .malformed}
                hasEntries = hasEntries || !list.isEmpty
            }
        }
        var hasApprovals=false
        if let graph {
            guard let data=graph as? Data,!data.isEmpty,data.count<=65_536,
                  let parsed=try? JSONDecoder().decode(SmartExclusionGraph.self,from:data),
                  parsed.edges.count<=SiteExclusionPolicy.maxEntries*SiteDependencyDiscovery.maxCandidates else{return .malformed}
            // Even orphaned or expired stored approvals require explicit
            // policy review. Never reinterpret them as permission to tunnel.
            hasApprovals=parsed.edges.contains{$0.decision == .approved}
            guard (try? parsed.effective(manual:[])) != nil else{return .malformed}
        }
        var off=false
        if let mode {
            guard let raw=mode as? String,["normallyOn","normallyOff"].contains(raw) else{return .malformed}
            off=raw=="normallyOff"
        }
        if off{return .normallyOff}
        if hasEntries{return .siteExclusions}
        if hasApprovals{return .dependencyPolicy}
        return .tunnelOnly
    }
}
