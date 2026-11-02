import Foundation

/// Explicit manual exclusions + confirmed graph children only. The gateway
/// receives exact DNS hostnames, NEVER physical IP-wide routes or wildcards.
/// This is deterministic and safe to exercise without starting a VPN.
enum SmartGatewayExclusionPolicy {
    static func approvedHosts(from effectiveExclusions: [String]) -> [String] {
        let hosts = effectiveExclusions.flatMap { SiteExclusionPolicy.routingHosts(for: $0) }
        return Array(Set(hosts.filter(SiteDependencyDiscovery.isScannableHost))).sorted()
    }
}
