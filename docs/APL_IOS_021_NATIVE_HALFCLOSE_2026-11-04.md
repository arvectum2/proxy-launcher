# iOS 0.2.1 — bounded native TCP half-close (4 November 2026)

## Why

The iOS packet tunnel uses an embedded Rust tun2proxy v0.8.3 TCP forwarder. The previous forwarding loop used tokio::join! to wait for both directions to return. If the upstream proxy had already sent FIN while the virtual client kept its write half open, the upstream socket could remain indefinitely in CLOSE_WAIT. A generic connection-pressure recycle helped only after thresholds were hit; it did not deterministically release the responsible socket. A parallel macOS investigation identified the same native lifecycle and prepared the original fix.

## Source-pinned iOS implementation

- Add Tools/tun2proxy-closewait-halfclose.patch, identical to the independently tested macOS native source patch, after the existing split DNS, flow-intent, scoped-direct, same-flow-retry and IPv4/IPv6 physical-family patches.
- Replace tokio::join! with a bounded two-direction completion operation. Upstream FIN allows up to 2 seconds for client-to-proxy forwarding to finish; client FIN allows up to 30 seconds for the reverse path to drain. Then drop the remaining async future and its socket halves instead of holding a half-closed upstream descriptor.
- The 2/30-second bounds are product trade-offs, not a guarantee that all legitimate half-closed TCP interactions remain unaffected. Run physical proxy throughput and upload/download regressions before a production rollout.
- Retain exact pinned upstream source commit e271de19683937f23d3f8f0eb4df0a61fc4a6e50, pinned Rust 1.98.1 toolchain, Smart3 callbacks, IPv4/IPv6 per-host routing and current App Store signing metadata.
- The reproducible builder mobile/ios/Tools/fetch_tun2proxy.py --with-simulator checks every patch before applying it, then generates device and ARM64 Simulator libraries. This repository tracks source patches and tool, not the 66 MiB generated XCFramework.

## Validation

- Rebuilt pinned Rust library for iPhoneOS and ARM64 iOS Simulator, including both Smart3/direct-routing callback symbols.
- Actual loopback TCP FIN regression where proxy server closed its sending half but virtual browser remained open: PASS.
- Rust: 4/4 half-close tests, 21/21 full lib tests PASS after independently cloning pinned upstream and applying all six patches in order.
- Python iOS source contract: 107 run, 0 failures, 1 skipped, including three new native half-close source checks.
- Swift Core: 135/135 PASS.
- Xcode 27.1 unsigned ARM64 Simulator app + PacketTunnel: BUILD SUCCEEDED.
- Pinned binary hashes as recorded by builder: iPhoneOS 77e90ef5d84a7367511249de18ea6ce980bb6e74899f322fa16ba7a2aebcde83; Simulator 57595ebbef93330b23b65655e1339906312449e5d84e7ebe1b7358c4607ff954.
- No owner device was changed; no live consumer VPN was restarted, no Apple version or advertisement metadata was modified.

## Remaining hard gates

1. Hosted GitHub iOS device/Simulator CI for exact PR commit must pass.
2. Physical controlled iOS testing must demonstrate server FIN/CLOSE_WAIT cleanup and continuing Safari and application network function under real upload/download, backgrounding, network switching and failover. Preserve the user own iPhone and proxy credentials; use an isolated disposable device and controlled upstream. The macOS physical QA is also distinct from this iOS proof.
3. Only after these gates should the patch be merged into a production release and assigned a new App Store build. It is not part of already-submitted 0.2.0(48). The source-only PR does not make that version safer until separately released.

Other iOS 0.2.1 stages: safe diagnostic PR #312 and clock-correction PR #313 are independent; both require successful hosted CI before merge. Real Apple-distributed 0.1.41 to 0.2.0 Keychain migration on a disposable iPhone remains independently unproven.
