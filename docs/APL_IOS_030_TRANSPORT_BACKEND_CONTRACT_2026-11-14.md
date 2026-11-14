# Unified inactive transport backend contract

## Scope and design decision

Existing HTTP/HTTPS/SOCKS5 profiles and existing routing are unchanged.
New protocols remain inactive in the production app; no new registered
provider IDs, entitlements, Keychain or native library link. SharedCore
compiles a portable contract and tests, not an adapter or an OS VPN manager.

The logical existing future Rust+Xray provider owns a single Go runtime
for VLESS/REALITY and standard WireGuard. A separate standalone AWG
provider process is required for the independent AWG Go runtime.
Actual Apple provisioned target/manager creation and approval are
separate pending work. Do not link two independently compiled Go
archives in the same process.

| Explicit selection | Logical provider | Evidence accepted for synthetic lab only |
| --- | --- | --- |
| VLESS/REALITY | Rust+Xray | TCP4 |
| Standard WG | Rust+Xray | TCP4/TCP6/UDP4/UDP6 |
| AWG1 fixed legacy matching fixture on pinned v3 | standalone AWG | raw IPv4/IPv6 only |
| AWG2/AWG3 | rejected | none |

The plan requires nonempty capability requests, rejects unmeasured
DNS/QUIC/MTU/app exclusions/direct/exact-host fallback, rejects all
production plans. This is bounded lab permission, not capability
advertising to end users. AWG format preview compared explicitly
with requested protocol; never pass an AWG preview as standard WG.
Unknown format/parser failures must not trigger fallback. Preview
does not prove the exact config or retain keys. Future native
provider must independently validate the fixture and profile revision.
The plan retains only opaque profile and revision UUIDs. Reuse of
the same profile/revision with a different protocol is refused.

## Switching contract

```
idle -> starting -> running
                     |
           explicit switch/stop
                     v
                  stopping
      native drained AND OS disconnected
                     |
          idle / start explicit next plan

starting/running/stopping -> failedClosed -> cancelTunnel once
```

Stop and drain are separate acknowledgements from OS disconnect.
The serial adapter must dispatch commands in order and tag native
and OS events with verified session token (epoch UUID + monotonic
generation). Old epochs and generations cannot take over the
current session; a duplicate acknowledgment cannot release the
other gate. Explicit user stop while switching clears pending start.
Wrong provider readiness, unexpected exit (including zero), or
startup/stop timeout cancels once, poisons coordinator and clears
pending plan. Fresh coordinator may be constructed only after
external reconciliation proves all owned providers stopped.
Contract has no implicit retry, new protocol, DIRECT or downgrade
effect. It is a pure state reducer, not thread-safe by itself:
future adapter must have a single serialized owner and enforce
native startup/drain deadlines, manager status and event binding.
Start-ready evidence must be measured by that adapter, not merely
a caller boolean. One active session is a modeled ownership rule,
not yet an observed native/OS process guarantee.

**Important:** disconnecting a PacketTunnel may restore direct
OS traffic. The state machine prevents implicit fallback commands;
it cannot claim zero packet leakage or continuous system-wide
kill switch during a provider transition. Actual routes, DNS,
session ownership, reconnect, timeouts, hardware and policy must
be measured separately. App must communicate a disconnect gap.

## Remaining gates

* Real provider-owned lease and adapter, explicit manager/provisioning
  and signed isolated test build; never modify working user profiles.
* Independent AWG version-specific interoperability and secure
  runtime config/storage path, app traffic; VLESS UDP/IPv6 if supported.
* MTU, DNS and QUIC acceptance, physical startup/stop and Wi-Fi/cellular
  switch, resource budget, route gap and no silent fallback.
* Final license/security and signing/App Store approvals.

## Verified 14.11.2026 11:35 MSK

Swift package full suite 268/268 PASS, including 13 new contract
tests (revised profile identities, same/different provider switching,
both acknowledgment orders, repeated/stale callbacks, failure,
wrong provider, startup cancellation, format mismatch and unsupported
capabilities). Python focused 33/33, including inactive-target guard.
Regenerated Xcode project contains only the additional pure Swift source.
Ordinary unsigned iPhoneOS Release build 0.3.0 (49) succeeded;
PacketTunnel nm has no _CGoInvoke, _CGoFree or _aplAWGSelfTest definitions.
No install/signing/account/profile mutation. Actual native adapter
and OS handoff not yet implemented or accepted.
