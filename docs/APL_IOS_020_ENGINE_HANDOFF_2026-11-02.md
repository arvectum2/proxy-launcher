# iOS 0.2.0 (48) — bounded tun2proxy engine handoff

**Scope:** source-only robustness improvement for automatic failover, return to primary and upstream socket-pressure recovery. No new network feature, proxy credentials or App Store operation.

## Failure mode

`PacketTunnelProvider.switchTo` previously called `tun2proxy_stop()`, slept a fixed 300 ms and then started another engine on the same serial `engineQueue`. Because `tun2proxy_run_with_cli_args` is synchronous and blocks that queue until exit, the sleep was not proof that the previous runner had finished. A slow shutdown could make iOS show a connected VPN while the replacement engine remained queued and DNS stopped responding.

## Fix

- `SharedCore/TunnelEngineHandoff.swift` calls the native stop synchronously, enqueues a completion barrier on the serial engine queue and awaits it with a 5-second timeout. The old engine must exit before the new `apply` can start.
- A lock-protected once-only gate prevents the queue's late completion from resuming a Swift continuation again after timeout. No endless polling, parallel tun2proxy engines or arbitrary longer sleeps.
- On a timed-out drain, `switchTo` uses the existing fail-closed path `cancelTunnelWithError`, instead of retaining a false connected state; the local diagnostic is the privacy-safe `VPN` code.
- Existing stop/cancel guards, profile selection, proxy credentials, network exclusions, Yandex SDK and release declarations remain unchanged. The same barrier is used for ordinary failover, return to primary and in-tunnel socket-pressure restart.

## QA / acceptance

- New executable Core tests: queued runner drains after stop, blocked runner times out, and late queued completion does not double-resume; **3/3 PASS**.
- New reason-classification unit: timeout maps to stable `VPN` code; **1/1 PASS**.
- Entire Swift Core suite **104/104 PASS**, including the new drain and diagnostic tests, after all changes.
- Python iOS 0.2 source contracts **41/41 PASS** after the final changes.
- XcodeGen regenerate adds exactly six references in generated pbxproj, and `plutil -lint` / `git diff --check` PASS.
- An unconstrained generic Simulator build initially attempted x86_64 against the ARM64-only `tun2proxy` static library and failed at linker architecture selection; **not** a Swift source failure. An isolated `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` Simulator Debug build subsequently **SUCCEEDED** (exit 0). The generated Xcode project includes the new core file in both the app and PacketTunnel targets; `plutil -lint` PASS.
- Real iPhone VPN/failover, public egress IP, third-party VPN state and traffic accounting have **not** been changed or retested in this source-only task. Physical two-proxy acceptance is a separate owner-controlled release gate.

**Release boundary:** Draft PR #296 remains open; no merge, TestFlight/App Store upload or changes to physical iPhone/user profiles. This document is not a certification of live upstream failover.

## Final local result (02.11.2026)

- Swift Core: 104/104 PASS; iOS 0.2 Python: 41/41 PASS; xcodebuild ARM64 iOS Simulator: BUILD SUCCEEDED; source identity 0.2.0 (48), generated pbxproj lint and diff check PASS.
- Source/generator changes are committed to Draft PR #296. GitHub exact-head Mobile iOS personal and macOS packaging workflows are queued on hosted runners; do not call them PASS until they complete.
- This is not a signed Release archive and was not installed on the physical iPhone.
