/// Actual transport capabilities, not user preferences. A Packet Tunnel
/// cannot turn an exact hostname into a safe physical DIRECT route using
/// NEIPv4/NEIPv6.excludedRoutes: those are global destination-IP rules.
/// Apple TN3120 also discourages selective alternate-interface forwarding.
enum AdaptiveRouteCapabilities {
    static let iosPacketTunnelExactHostDirect = false
    static let iosIndependentNoProxyProbe = false
}
