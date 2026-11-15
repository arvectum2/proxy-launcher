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
