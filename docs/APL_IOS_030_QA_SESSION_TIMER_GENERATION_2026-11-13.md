# iOS 0.3.0 — generation-safe bounded PacketTunnel QA callbacks

Date: 13 November 2026. Scope: **Debug-only QA safety hardening**, before
hardware Wi-Fi/LTE or DNS/UDP/QUIC acceptance.

## Failure mode eliminated

The original `PacketTunnelProvider.startTunnel` scheduled two independent
`DispatchQueue.main.asyncAfter` actions for physical QA:

- `qaStopAfterSeconds`: cancel the test VPN after 5–30 seconds or 95 seconds
  for specifically gated radio handoff QA;
- `qaResetDirectAfterSeconds=17`: invalidate synthetic experimental exact-host
  DIRECT evidence during a bounded QA session.

Both checked only `!self.stopping`. A subsequent `stopTunnel` followed by
`startTunnel` reset `stopping` to false; an earlier test's timer could then
cancel the **new** VPN session or unexpectedly reset the new session's
SmartFlow evidence.

## Implementation

- New `SharedCore/TunnelQACallbackGate.swift` uses a locked, monotonically
  incrementing generation. A fresh `startTunnel` begins a session; every
  `stopTunnel` invalidates its generation.
- Both delayed **Debug QA callbacks** capture their own token and use
  `performIfCurrent`, which serializes generation comparison and execution
  against concurrent stop/restart. A recursive lock accommodates synchronous
  stop notification during callback.
- Neither normal production settings, proxy selection, routing, entitlement,
  user profiles, Keychain nor Release timer behavior changes.
- The existing host and extension bounded physical QA time limits remain
  intact; a new legitimate QA session receives its **own** timeout.

## Verified offline

- Swift CoreTests **232/232 PASS**, including six new gate tests covering
  stale callbacks, stop/reconnect, repeated start, synchronous invalidation
  and 128 concurrent stale callback attempts.
- iOS Python source/contract tests **344 PASS + 1513 subtests**; four new
  `unittest` source contracts also passed under dependency-free discovery.
- Full generic unsigned iPhoneOS Release App+PacketTunnel **BUILD SUCCEEDED**.
- Full unsigned iPhoneOS Debug QA target, compiled with
  `APL_RUN_EXPLICIT_VPN_QA`, **BUILD SUCCEEDED**.
- `xcodegen` regenerated Xcode project file to include the new SharedCore
  source in its relevant targets.

**Not accepted:** physical radio loss/handoff, DNS/UDP/QUIC leak,
production fail-closed end-to-end, and App Store release. The six unit tests
validate callback ownership only; they are not equivalent to a signed real
iPhone NetworkExtension test. No physical iPhone or saved owner data changed.

PRs #377 (unexpected native engine exit fail-closed), #378 (bounded UDP
witness) and #379 (encrypted Files backup safety) are separate, exact-head CI
green (11/11 each) and remain open/unmerged pending their owner-specific gate.
