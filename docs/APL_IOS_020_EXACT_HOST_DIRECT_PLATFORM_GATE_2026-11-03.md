# iOS 0.2.0 — consumer Safari exact-host DIRECT: platform decision

Date: 2026-11-03. Scope: ordinary App Store consumer iOS, no enterprise enrollment, no gateway, and no unrelated shared-IP traffic leaking around the proxy.

## Required behavior

1. APL is on; user excludes site A; Safari redirects to previously unseen auth.A.
2. Two distinct proxy connection errors occur while the upstream proxy is healthy.
3. APL independently proves no-proxy egress for auth.A.
4. Only connections to **exactly auth.A** use DIRECT, even if another domain shares its destination IPv4 or IPv6 IP. Preserve QUIC behavior, network-change rollback, expiration and user override.
5. This requires a documented, supported iOS consumer API. Silent IP-wide bypass, an MDM requirement, new gateway, or a Wi-Fi TLS probe without actual Safari egress proof do not satisfy the requirement.

## Platform capability review (Apple primary documentation, 2026-11-03)

| API | Scope | Does it satisfy the contract? |
| --- | --- | --- |
| NEPacketTunnelNetworkSettings + NEIPv4Route/NEIPv6Route.excludedRoutes | Supported consumer device-wide Packet Tunnel | **No**: exclusions match destination IP/prefix, not hostname. Another domain on that IP also bypasses the proxy. |
| NETunnelProviderManager.excludedDomains | iOS MDM **per-app** VPN only | **No** for consumer device-wide VPN. Valid only for a separately enrolled/managed product. |
| NEAppProxyProvider | iOS MDM per-app deployment | **No** for unmanaged Safari traffic. |
| NETransparentProxyProvider | macOS | **No** on consumer iOS. |
| NEOnDemandRuleEvaluateConnection | VPN state | **No**: starts/disconnects VPN, cannot route an individual hostname while the tunnel stays active. |
| NEURLFilterManager (iOS 26+) | Consumer URL allow/block filtering | **No**: filter verdicts are allow/block, not physical egress/routing selection. |
| NWConnection requiredInterfaceType | Independent diagnostic TLS socket | **No**: a successful socket on Wi-Fi does not establish that Safari switched only that hostname outside the VPN. TN3120 discourages selective alternate forwarding of claimed traffic. |

References:
- [Apple: Routing your VPN network traffic](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic)
- [Apple TN3120: Expected use cases for packet tunnel providers](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers)
- [Apple: NETunnelProviderManager (iOS per-app VPN requires MDM)](https://developer.apple.com/documentation/networkextension/netunnelprovidermanager)
- [Apple: excludedDomains (per-app VPN only)](https://developer.apple.com/documentation/networkextension/netunnelprovidermanager/excludeddomains)
- [Apple: URL filters (allow/block, not route)](https://developer.apple.com/documentation/networkextension/url-filters)

## Current source/hardware facts

- Available: default automatic **verified first-party** dependency expansion, parent-scoped domain groups, manual add/revoke/reject/remove, bounded 7-day discovery; Rust per-flow CONNECT failures and adaptive local diagnostics.
- SharedIPRouteGuard knows about observed IP conflicts but **cannot prove that no unknown other host** shares a CDN IP.
- SharedCore/AdaptiveRouteCapabilities.swift correctly sets iosPacketTunnelExactHostDirect=false and iosIndependentNoProxyProbe=false. Do not change these booleans without a supported mechanism and reproducible physical no-leak evidence.
- Prior physical iPhone 13 (iOS 27.2) testing: two distinct failed proxy sessions and a separate TLS probe; **no proven Safari per-host physical route** and no validated unrelated same-IP host isolation. See docs/APL_IOS_SMART3_PHYSICAL_EGRESS_QA_2026-11-02.md.
- No documented Apple API found that makes the full set of requirements possible for **ordinary unmanaged consumer iOS**. Therefore the original Smart3 zero-touch feature is **BLOCKED BY PLATFORM**, not merely waiting on implementation or tests.

## Feasible engineering paths and product limits

1. **Consumer iOS conservative behavior**: automatic first-party discovery, local failed-host suggestions, grouped manual approval with warning that shared-IP traffic may also bypass. This is implemented, but is **not** the requested fully automatic timeout-to-no-proxy behavior.
2. **Managed enterprise variant**: a separate MDM per-app VPN offering with domain exclusions, limited to managed deployments and requiring separate QA; **not** a substitute for consumer App Store operation.
3. **macOS-only flow routing**: NETransparentProxyProvider can be evaluated for macOS independently, not ported as-is to consumer iOS.
4. **Remote gateway**: potentially allows server-side hostname routing, but was **rejected by the owner** for this iOS requirement and is not selected.
5. **IP-wide automatic bypass**: explicitly rejected due unknown shared-IP domains; do not ship behind the default-on switch.

## Release gate

Grouped UX and localization can be marked complete after source QA. The zero-touch exact-host DIRECT function must **not** be claimed DONE, and iOS 0.2.0 with the original scope must not be published. Shipping a conservative suggestion-only mode instead requires the owner's explicit product decision changing the release promise. Do not touch actual iPhone VPN, production proxy credentials, advertisements, privacy disclosures, Apple review or Watchdog as a workaround.
