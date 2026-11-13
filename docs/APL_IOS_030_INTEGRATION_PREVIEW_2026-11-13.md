# iOS 0.3.0 — source integration preview (NOT a release candidate)

Date: 2026-11-13. This branch is isolated from production
`main=0a68fbb4a5984ee59530314c4310bfaa71c9e3ea`; no existing PR was
merged to `main`, no signed app installed and no physical iPhone operated.

## Contents of the unified preview

This branch **cherry-picks** the five reviewed *code/test* commits (not
the independent checkpoint commits) from four unmerged PRs, in order:

| Source PR | Original code commit | Integrated feature |
| --- | --- | --- |
| #377 | `083101d64063aa231d38435ab23f444a183532bf` | Unexpected native packet engine exit cancels NetworkExtension instead of reporting a broken Connected tunnel |
| #378 | `8a02f6c11`, `fcfa6c5b3` | Bounded disposable opt-in IPv6 UDP echo witness and Windows `unittest`-compatible safety gates |
| #379 | `bb0be34fc` | Encrypted `.aplbackup` export filenames are unique; import reads bounded File Provider chunks |
| #380 | `fe80c1626` | Session-scoped Debug PacketTunnel delayed QA timers; stale callbacks cannot stop a reconnected tunnel |

The overlapping `PacketTunnelProvider.swift` and generated Xcode project
content merged without source conflicts. The *only* cherry-pick conflicts were
concurrent append entries in the active roadmap; both edits were preserved,
and the #379 Files backup QA document retained. XcodeGen was rerun.

## Verified on combined source

- **241/241 Swift CoreTests PASS**, including new native engine-exit,
  backup, QA generation and multi-thread race tests.
- **357 iOS Python tests PASS + 1527 subtests PASS**.
- **14 dependency-free `unittest` cross-source contract tests PASS**.
- Generic unsigned **iPhoneOS Release App + PacketTunnel BUILD SUCCEEDED**.
- Generic unsigned **iPhoneOS Debug physical QA target BUILD SUCCEEDED**
  with `APL_RUN_EXPLICIT_VPN_QA`; no test was executed on a physical device.
- `git diff --check` PASS; working tree otherwise clean before checkpoint.

## Not accepted / explicit approval gate

The source passes combined offline tests but **is not an approved release
candidate**. Remaining independent acceptance gates: signed hardware
DNS/UDP/QUIC leak proof (including witness server source count), Wi-Fi/LTE
loss/handoff and fail-closed, native VLESS/Reality/WireGuard/AmneziaWG
backend provenance and packet handoff, CloudKit two-device private sync,
complete Files Browse → decrypt → import, original profiles/Keychain
byte-preservation and final App Store distribution approval.

Do not merge any PR, enable unsupported protocols, install on the user's
iPhone, alter its live VPN or submit to App Store merely because this
integration preview's offline tests passed.
