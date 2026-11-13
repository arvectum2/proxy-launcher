# iOS 0.3.0 — native PacketTunnel unexpected-exit fail-closed

Date: 2026-11-13. Scope: Swift-only; no Rust binary, live proxy profile, Keychain, entitlements, advertisements, VPN settings or public App Store build changed.

## Defect and bounded remediation

The PacketTunnel used to log nonzero `tun2proxy_run_with_cli_args` return and leave NetworkExtension reporting Connected. A return of zero without an intentional stop is also an unexpected exit: the native packet router is no longer servicing traffic.

`TunnelEngineExitGate` now assigns a monotonically increasing, lock-protected generation to every native runner. A native return (regardless of code) marks the current generation failed exactly once and calls `cancelTunnelWithError` to shut down the VPN. The same gate is explicitly invalidated *before* intentional `stopTunnel` and before `switchTo` drains the old serial runner. A delayed exit callback from an old generation cannot cancel a replacement. The 350-ms start handshake also checks that the new runner remains live, rather than marking a dead engine Connected.

This is session-state fail-closed on engine death, not a verified system-wide kill switch; user-defined excluded routes and the upstream proxy endpoint still follow the deliberately configured routing policy.

## Verification

- New Swift XCTest: 5/5 PASS — premature clean exit, stop suppression, stale generation, 64 concurrent exit owners, queued cancellation suppression.
- Full Swift package suite: 231/231 PASS.
- Python source gates: 343/343 PASS plus 1513 subtests.
- Unsigned iPhoneOS Release App+PacketTunnel: BUILD SUCCEEDED with 0.3.0(49) command-line version overrides. Existing Swift concurrency and metadata warnings are tracked separately.
- Unsigned ARM64 iOS Simulator Debug App+PacketTunnel: BUILD SUCCEEDED with explicit ARCHS=arm64 / EXCLUDED_ARCHS=x86_64, same source and pinned native artifact. The generic default x86_64 attempt had only an architecture-link mismatch.

## Remaining physical acceptance

A signed, bounded hardware fault-injection session on an approved test iPhone must prove VPN transitions to OFF/failed if the native runner or isolated upstream dies unexpectedly; verify user data bytes and saved Keychain remain unchanged. No physical kill-switch, DNS leak, UDP/QUIC, Wi-Fi/LTE transition or full recovery claims are made by source-only tests. Avoid the owner's original commercial proxies and production DIRECT routes for destructive tests. No iOS 0.3.0 release until remaining gates.
