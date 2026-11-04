/// Physical, per-flow exact-host egress; never an IP-wide excludedRoutes rule.
/// No pre-approval from Apple is claimed. Actual App Review decides acceptance.
enum AdaptiveRouteCapabilities {
#if targetEnvironment(simulator)
    // Simulator cannot establish iPhone physical interface-specific egress.
    static let iosPacketTunnelExactHostDirect = false
    static let iosIndependentNoProxyProbe = false
#else
    // Physical iPhone 13 proved both recovered Safari TLS and neighbor proxy.
    static let iosPacketTunnelExactHostDirect = true
    static let iosIndependentNoProxyProbe = true
#endif
}
