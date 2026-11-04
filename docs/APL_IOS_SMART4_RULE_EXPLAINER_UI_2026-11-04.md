# Smart Routing 4.0, phase 2a — explain exclusion rules in iOS UI (4 Nov 2026)

## Scope and user interaction

- A 44×44-point accessible information button appears beside every explicitly listed exclusion and each dependency inside an expanded site. The VoiceOver label includes the user-visible hostname.
- Tapping the button opens a non-destructive explanation using only the currently visible, staged manual exclusion list and dependency graph, evaluated by the same pure SmartFlowRoutingPolicy introduced in PR #315.
- MANUAL means a user-added rule; APPROVED means an authorized related host; NO_RULE means this hostname has no matching domain authorization; UNVERIFIED_HOST means a raw IP or hostname which exact-host routing cannot verify.
- In all cases, the alert includes an explicit reminder that rule edits require saving and reconnecting to apply. For raw IPs, the caution explains that shared-IP bypass affects unrelated hostnames.
- The UI intentionally does not report measured network traffic or claim that Apple's IP-based excludedRoutes enforce true hostname isolation. No new DIRECT permission is granted, and no PacketTunnel, proxy credential, Keychain, DNS, route writer or VPN configuration changes occur.

## Localization and accessibility

- All displayed human-readable explanatory strings reuse existing SmartExclusions.strings keys available in all 64 current iOS UI languages, avoiding guessed machine translations.
- No host, IP, password or URL is logged or persisted by this feature; hostnames only appear where already shown in the exclusion list or accessibility label.
- Both manual and graph-linked rows include an explicit accessibilityIdentifier, 44-point touch target and appropriate VoiceOver label.
- This is a read-only preview; the actual networking safety gate for per-flow exact-host routing remains outside this change.

## Verification

- Python source contracts: three new cases check 64/64 language keys, both row button placements and read-only/preview behavior.
- Swift Core 146/146 PASS; Python iOS contracts 107 tests, 0 failed, 1 skipped. ARM64 iOS Simulator app+PacketTunnel BUILD SUCCEEDED.
- Controlled UI XCTest SmartExclusionsUITests.testSmart4ManualRuleExplanationPreviewAndNoSave: 1/1 PASS on newly-created iPhone 13 / iOS 27.0 simulator; xcresult status Passed with 0 failures; temporary simulator deleted afterward.
- git diff --check PASS.
- No owner iPhone, production profile or current iOS 0.2.0 App Review submission changed.

## Remaining Smart4 work

- Phase 2b: optional privacy-preserving dry-run comparison of staged Smart4 decisions vs on-device Smart3 path with explicit user opt-in and a bounded in-memory buffer, without browsing history or automatic routing actions.
- Phase 3: controlled physical iPhone E2E with independent network egress and shared-CDN IPv4/IPv6, UDP/QUIC and rollback before enabling new exact-host routing or calling it network-functionality complete.
