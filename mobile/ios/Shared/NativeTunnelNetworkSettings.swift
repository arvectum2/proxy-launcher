import Foundation
import NetworkExtension

/// Candidate settings only. Deliberately not called by shipping VPNController
/// or PacketTunnelProvider. Building this object does not validate actual
/// OS routing, DNS leak resistance, peer reachability or a kill switch.
enum NativeTunnelNetworkSettings {
    static func make(_ plan: NativeTunnelRoutePlan) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress:plan.remoteAddress)
        settings.mtu = NSNumber(value:plan.mtu)
        let v4 = NEIPv4Settings(addresses:[plan.ipv4Address],subnetMasks:["255.255.255.255"])
        v4.includedRoutes = [NEIPv4Route.default()]
        v4.excludedRoutes = []
        let v6 = NEIPv6Settings(addresses:[plan.ipv6Address],networkPrefixLengths:[128])
        v6.includedRoutes = [NEIPv6Route(destinationAddress:"::",networkPrefixLength:1),NEIPv6Route(destinationAddress:"8000::",networkPrefixLength:1)]
        v6.excludedRoutes = []
        let dns = NEDNSSettings(servers:plan.dnsServers)
        dns.matchDomains = plan.dnsMatchDomains
        dns.matchDomainsNoSearch = true
        settings.ipv4Settings = v4; settings.ipv6Settings = v6; settings.dnsSettings = dns
        return settings
    }
}

#if DEBUG && APL_NATIVE_IP_ROUTE_REVIEW
extension NativeTunnelNetworkSettings {
    /// Offline mapping only; no setTunnelNetworkSettings caller. Keep DNS and
    /// both included-route families unchanged; no implicit peer exemption.
    static func makeExplicitIPReview(_ plan:NativeIPSplitRoutePlan)->NEPacketTunnelNetworkSettings {
        let settings=make(plan.base)
        settings.ipv4Settings?.excludedRoutes=plan.ipv4Exclusions.map {NEIPv4Route(destinationAddress:$0.address,subnetMask:$0.ipv4Mask!)}
        settings.ipv6Settings?.excludedRoutes=plan.ipv6Exclusions.map {NEIPv6Route(destinationAddress:$0.address,networkPrefixLength:NSNumber(value:$0.length))}
        return settings
    }
}
#endif

#if DEBUG && APL_NATIVE_PROVIDER_INTEGRATION && APL_NATIVE_SYNTHETIC_RUNTIME && APL_NATIVE_SYNTHETIC_SPLIT_ROUTE && APL_NATIVE_AWG_CANDIDATE
extension NativeTunnelNetworkSettings {
    /// Actual scoped lab objects; no default routes, DNS or arbitrary input.
    static func makeSyntheticSplitRoute()throws->NEPacketTunnelNetworkSettings {
        let plan=try NativeSyntheticSplitRoutePlan.prepare()
        let settings=NEPacketTunnelNetworkSettings(tunnelRemoteAddress:"192.168.1.80")
        let v4=NEIPv4Settings(addresses:["192.0.2.1"],subnetMasks:["255.255.255.255"])
        v4.includedRoutes=plan.included.filter{!$0.isIPv6}.map{NEIPv4Route(destinationAddress:$0.address,subnetMask:$0.ipv4Mask!)}
        v4.excludedRoutes=plan.excluded.filter{!$0.isIPv6}.map{NEIPv4Route(destinationAddress:$0.address,subnetMask:$0.ipv4Mask!)}
        let v6=NEIPv6Settings(addresses:["2001:db8::1"],networkPrefixLengths:[128])
        v6.includedRoutes=plan.included.filter{$0.isIPv6}.map{NEIPv6Route(destinationAddress:$0.address,networkPrefixLength:NSNumber(value:$0.length))}
        v6.excludedRoutes=plan.excluded.filter{$0.isIPv6}.map{NEIPv6Route(destinationAddress:$0.address,networkPrefixLength:NSNumber(value:$0.length))}
        settings.ipv4Settings=v4;settings.ipv6Settings=v6;settings.mtu=1280
        return settings
    }
}
#endif
