# Smart Routing 4.0 — aggregate-only source dry-run (4 November 2026)

## Scope

Pure read-only, explicit opt-in QA accumulator compares a proposed exact-host Smart4 route with separately observed Smart3 transport evidence. No live traffic interception, browsing history, network route mutation, credentials, hostname/IP persistence or analytics.

The model lives in mobile/ios/SharedCore/SmartRouteDryRunAudit.swift and is not called from AppViewModel, ExclusionsView or PacketTunnelProvider.

- Disabled by default: zero samples even if observe is invoked.
- Explicit enable with Smart4DryRunAudit(optedIn: true); every opt-in transition clears all old counters.
- Transient hostname/IP arguments are used only in pure SmartFlowRoutingPolicy.explain and are not retained.
- Only separately confirmed via-proxy or direct observations can yield match or mismatch. Unknown and inferred-only-from-IP evidence are always inconclusive.
- Snapshot has only primitive counters: observed, matches, mismatches, inconclusive, proposed DIRECT/PROXY, enabled flag and saturation flag.
- Maximum 256 samples per opt-in session, then stop recording.

## Evidence boundary — important limitation

This is **not yet a live comparison**. The actual iOS Smart3 route uses IP-wide NetworkExtension excludedRoutes plus tun2proxy. DNS resolution, connection readiness or a shared CDN IP cannot prove exact-host transport. The evidence enum is supplied by a future independent lab observer. Callers asserting a confirmed enum without independently verifying packet egress would produce misleading numbers; no such live caller is installed.

No PacketTunnel changes, no automatic UI display, and no browsing-event journal. The existing unsaved-rule Smart4 explanation UI remains unchanged.

## Tests and rollout

Swift tests exercise opt-in gating, independently confirmed matches/mismatches, manual/approved/expired dependencies, sibling CDN IPv4/IPv6 identities, unknown/IP-inferred observations, invalid/raw-IP fail-closed and bounded counts/reset. Python source contracts forbid telemetry sinks, raw private strings in summary or runtime PacketTunnel use.

Next: independently observe real packet egress only in controlled synthetic QA flows and compare; then disposable-device test of shared CDN IPv4/IPv6, QUIC/UDP, DoH, failover and rollback. Real routing behavior must not change until physical verification.

Separate hardware QR QA remains partially blocked: real iPhone 13 QR pixel decoding passed, but physical XCTest still times out enabling automation after matching Xcode 27.2 retry; stale CoreSimulator service version also logged. This is not evidence of Smart4 network behavior.

## Verified source QA (4 November 2026)

- Full Swift Core: **159/159 PASS** (8 new aggregate dry-run tests).
- iOS Python source/locale contracts: **117 run, 0 failures, 1 skipped** (3 new privacy/isolation assertions).
- Xcode 27.1 unsigned ARM64 iOS Simulator app and PacketTunnel: **BUILD SUCCEEDED**; the generated Xcode project includes the newly added shared-core source.
- No real egress measurement, live route change, user VPN restart, Apple submission or iPhone installation was performed for this Smart4 feature.
