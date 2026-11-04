# iOS consolidation on top of macOS App Store release branch (4 Nov 2026)

## Why a new consolidation PR

After the macOS 0.2.22 work was merged into main by PR #310
(main base 4e7b58084d1973aebdd6fb832abfb7dcb6863698), six previous
independent iOS PRs became CONFLICTING against the new canonical main.
Directly merging their stale .agent/current-task.yaml, roadmap or generated
Xcode project would silently lose the newer macOS state.

This integration is deliberately based on that latest main. It transfers
only scoped reviewed iOS sources and source contract tests from:

- PR #330: compiled local QR app/PacketTunnel inclusion witness.
- PR #331: typed, localized privacy-safe QR scanner failures.
- PR #332: correct 64-locale translations and redacted encrypted-backup errors.
- PR #333: safe profile CRUD error reporting and 64-language keys.
- PR #335: offline JSON provider import (single, array or proxies wrapper).
- PR #336: bounded <=16 KiB chunk file read, refusing >256,000 bytes before
  loading entire supplier documents into memory.

The overlapping ProxyImportView was merged by hand to retain QR camera typed
errors, the JSON file picker and the bounded file reader at the same time.
The project.pbxproj is generated from project.yml, not copied from any old
branch. All 64 ProxyImport.strings retain stable localization keys. The
App/ProxyImportUX English fallback also mentions JSON.

## Scope and safety

The macOS released/network code and iOS PacketTunnelProvider from merged
PR #310 remain byte-for-byte identical to current main. There is NO
native tun2proxy or traffic routing change in this integration.
The iOS FIN/CLOSE_WAIT native experiment remains in unmerged draft PR #314.
Other draft PRs #311 and #318 are also excluded.

The original signed iOS 0.2.0(48) in Apple Review was built from earlier
source f0a93f8a before QR. The unsigned LOCAL iOS Simulator app compiled in
this integration still carries project version metadata 0.2.0(48), but is
NOT that Apple-signed IPA. No App Store version number, App Review, signing
entitlements, user iPhone, VPN, Keychain, proxy credentials or real network
connections were changed.

The owner explicitly deferred cross-iPhone QR transfer acceptance until
after the first actual QR-containing App Store release. No post-release
hardware test is claimed here.

## Local integrated regression

From current macOS main at 4e7b5808 plus six iOS source changes:

- Swift Core **171/171 PASS**, including all JSON and bounded file-reader
  boundary/invalid-input tests.
- iOS Python contracts and source/locale regression **168 tests run,
  one skipped**, no failures.
- XcodeGen + unsigned **ARM64 iOS Simulator App + PacketTunnel BUILD PASS**.
- Verified compiled Mach-O symbols for ProxyImportStructured.json,
  ProxyImportFileReader.readUTF8, ProfileBackupUX.message,
  ProfileMutationUX.saveFailed and QR scanner.
- Independent compiled QR witness PASS for sender, QR image, share codec
  and camera scanner plus exact app and PacketTunnel bundle IDs.
  Its result explicitly reports App Store publication, Apple-signed IPA and
  two-iPhone QA all **false**.
- All **64/64** ProxyImport.strings pass Apple plutil validation.
- No diff against current main iOS PacketTunnelProvider or macOS released
  source. Nothing deployed on personal hardware.

The integration PR must also pass FULL exact-head GitHub CI and be mergeable
before entering main. Previous PRs showing canceled macOS GitHub runners
were not treated as proof of successful checks. Only AFTER this integration
PR is merged may the six now-superseded PRs be closed with a reference to
the exact merged source. Preserve archived individual task checkpoints
and change their status to completed only when that merge is confirmed.
