# iOS 0.2.1 / APL-IOS-021 — privacy-safe connection diagnostics (4 Nov 2026)

## Boundary and baseline

- Isolated worktree/branch: feat/ios-021-connection-diagnostics-20261104, based on origin/main 5ed0c3df.
- Current App Store submission 0.2.0(48) remains WAITING_FOR_REVIEW and is not mutated. The candidate does not change bundle identifiers, provisioning, build numbers, advertising, Apple privacy answers, profiles, Keychain or the live user VPN. No release signing or submission was attempted.
- The parent macOS CLOSE_WAIT root-fix remains separate; this work intentionally does not touch tun2proxy lifetime, proxy sockets or macOS installed apps.

## Actual defect and change

The toggleVPN() error alert, the macCatalyst repair alert and VPNController.prepare() status previously rendered arbitrary error.localizedDescription. A raw NSError can carry an upstream proxy hostname, a username, a URL or other technical secrets; showing that data as an actionable alert was inappropriate.

- ProxyFailureReason.safeDisplay(for:translate:) now outputs only a static, stable error code plus a translated, predefined recovery message. It never passes arbitrary error descriptions, hostnames, userInfo or raw URLs to UI.
- recoveryGuidanceKey uses four existing reviewed Localizable.strings keys, present in all 64/64 shipped UI languages, with conservative actions for DNS/TCP/timeout, authentication/HTTP 407, TLS/protocol mismatch and the remaining generic classes. No unsupported new translations were invented.
- AppViewModel.toggleVPN() and repairVPNConfiguration() use the same safe message builder. VPNController.prepare() also uses this builder instead of the raw error. VPNController.userFacingError() preserves its deliberately authored NetworkExtension disabled/stale/invalid guidance but converts other errors to typed, non-sensitive diagnostic errors.
- This deliberately does not auto-modify VPN configuration or bypass proxy security and does not imply that a successful CONNECT means site content loaded.

## Verification

- swift test --package-path mobile/ios: 138/138 PASS (including 3 new safe-display cases).
- python3 -m unittest discover -s tests -p 'test_ios_*.py': 104 tests run, 0 failures, 1 skipped; 64-locale contract checked; synthetic 0.1.41 storage/Keychain source compatibility contracts retained.
- xcodebuild unsigned iOS Simulator application + PacketTunnel full build on ARM64, Xcode 27.1: BUILD SUCCEEDED. Initial generic simulator build also targeted x86_64 and could not link pinned arm64-only tun2proxy; the explicit ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build succeeded.
- git diff --check: PASS.

## Following stages / honest limitations

- APL-IOS-UPGRADE-020: source-reconstructed 0.1.41→0.2.0 App Group 8/8 fixture and schema checks already passed in release evidence; real Apple-distributed 0.1.41→0.2.0 Keychain retention on a disposable, properly provisioned iPhone is not yet independently proven. Never downgrade or overwrite the owner's active iPhone/proxies for this.
- APL-IOS-021-PRESSURE: apply the socket-owner root fix only after separate macOS investigation identifies a shared cause and a targeted iOS regression is justified. Existing iOS pressure policy is not proof of deterministic socket cleanup.
- Then Smart Routing 4.0, iCloud exclusions syncing and shared rule-engine/Proxifier-like research in separate, capability-gated scopes.
- Review/build/source acceptance does not imply publication of 0.2.1. Apple distribution and any production metadata changes require their own release acceptance.
