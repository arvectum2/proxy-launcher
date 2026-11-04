# Smart Routing 4.0, Phase 1: deterministic route provenance (4 November 2026)

## Scope

Source-only, read-only, no network behavior change. The current SmartFlowRoutingPolicy is a prototype for domain-scoped routing decisions; it is not wired to the iOS PacketTunnelProvider. Existing direct/proxy site routing and Apple NetworkExtension excludedRoutes remain unchanged. This phase does not enable any new DIRECT route or inspect browsing history.

## Implemented

- SmartRouteEvaluation couples the existing exact-host disposition (PROXY/DIRECT) to a privacy-safe code:
  - MANUAL: manual user exclusion and its built-in matching hosts / www aliases.
  - APPROVED: a graph-approved dependent hostname while its parent exclusion remains active and the edge has not expired or been denied.
  - NO_RULE: a valid DNS hostname without an effective direct exception.
  - UNVERIFIED_HOST: nil, raw IP, wildcard, invalid syntax or a noncanonical hostname; always PROXY.
- A manual source has precedence if a hostname occurs in both the manual and graph-derived sets.
- All reasons are fixed enum values. No domain names, resolved IPs, URLs, credentials or page data are stored, serialized as a traffic journal or embedded in reason identifiers.
- The old decide(host:resolvedIP:) method now delegates to explain(host:resolvedIP:). It returns exactly the same disposition as the pre-Smart4 method; no routing writer or Packet Tunnel integration was introduced.

## Acceptance evidence

- Independent reference evaluator recreates the pre-Smart4 permission derivation using SmartExclusionGraph.effective, SiteExclusionPolicy.routingHosts and SiteDependencyDiscovery.isScannableHost. This matrix compares manual variants, graph expiry, valid/untrusted hostnames and IPv4/IPv6 shared addresses.
- Five new Swift Core regression tests check manual/approved provenance, pending/rejected/orphan/expired fail-closed behavior, literal-IP and invalid-host safety, reason code stability and exact legacy disposition equivalence.
- Full Swift Core: 146/146 PASS (includes five new route-provenance tests). iOS Python source contracts: 104 run, 0 failed, 1 skipped. Xcode 27.1 unsigned ARM64 iOS Simulator app+PacketTunnel build: BUILD SUCCEEDED. git diff --check PASS.
- No physical iPhone or live user profile was touched.

## Next phases and hard gates

1. Add a localized, accessible route explanation in diagnostics/UI using approved wording for all current 64 languages. Do not emit personal domains or credentials into logs or analytics.
2. Add a read-only dry-run comparison of proposed Smart4 policy and actual Smart3 packet path. No implicit modifications.
3. Only after controlled physical iPhone exact-host IPv4/IPv6 + shared-IP/safari/UDP/QUIC/failover/rollback E2E and Apple-supported transport review may new direct-routing behavior be enabled in a separately versioned release.

The current Apple App Review submission iOS 0.2.0(48), paid proxy profiles, Keychain, Yandex ads and VPN settings are unchanged.
