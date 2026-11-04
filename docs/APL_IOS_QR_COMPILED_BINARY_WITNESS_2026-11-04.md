# iOS QR compiled artifact witness — 4 November 2026

## Reason and method

The prior source-only Git check is necessary but cannot prove that QR code was
compiled into an app. The new read-only verifier
mobile/ios/Tools/verify_qr_compiled_app.py additionally checks an actual
locally built .app bundle:

- Source Git ancestry and required QR files via the earlier fail-closed gate.
- Production app bundle ID ru.arvectum.proxylauncher.ios and embedded
  Arvectum Packet Tunnel.appex with the expected PacketTunnel bundle ID.
- Real compiled Swift symbols using nm + swift-demangle: ProxyShareView,
  ProxyShareQRCode.image, ProxyProfileSharing.deepLink and camera scanner
  ProxyQRScanner.Coordinator.metadataOutput.
- Modern Xcode Debug executable is often only a stub; the source-bearing
  app debug.dylib is also scanned.

The verifier does not connect to Apple or the network, open personal profiles,
change a VPN, access user Keychain, install an app or use an iPhone.

## Actual test result

- Exact source ref: 6a6616953f1b12b0480ee14fc8dc4bc5c46e99b3.
- XcodeGen + unsigned ARM64 iOS Simulator App and PacketTunnel build: PASS.
- Four real compiled QR symbols and exact bundle/extension IDs: PASS.
- Nine hermetic portable negative/positive tests: 9/9 PASS.
- Full iOS Python source/locale: 142 tests (one skipped), no failures.
- Full Swift Core: 159/159 PASS.
- Evidence explicitly reports apple_signed_archive_verified=false,
  app_store_publication_verified=false, two_iphone_qa_verified=false.

Example after building the current Git ref:

    python3 mobile/ios/Tools/verify_qr_compiled_app.py --source-ref HEAD --app "/tmp/apl-ios-qr-binary-attestation-20261104/DerivedData/Build/Products/Debug-iphonesimulator/Arvectum Proxy Launcher.app"

This path is a local QA DerivedData example, not a published artifact.

## Critical version distinction

The newly compiled unsigned local application has the old project metadata
0.2.0 (48), which was deliberately NOT changed in this QA task. Apple's
earlier signed 0.2.0 (48) was built from Git source f0a93f8a, BEFORE QR
existed. The two builds are NOT equivalent. Never infer that the Apple
0.2.0 (48) includes QR from this local Debug result.

The future QR-capable App Store release must freeze a separate exact Git
ref, verify its signed IPA's contents, then go through Apple's review.
The owner decided that actual two-iPhone QR exchange testing will follow
the FIRST QR-containing publication, with discovered bugs fixed in a
subsequent update. Native FIN/CLOSE_WAIT PR #314 remains DRAFT pending
independent physical VPN/egress QA. iCloud sync remains deferred.
