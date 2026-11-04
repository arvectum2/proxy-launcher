# iOS QR profile sharing — physical iPhone QA, 4 November 2026

## Confirmed on device

A user-authorized physical test was performed over ARC using the paired iPhone 13 on iOS 27.2 with Developer Mode enabled. The existing App Store Arvectum Proxy Launcher 0.1.41 (build 46) was present before and remained present afterward.

An independent Apple Development-signed QA application was built and installed with bundle identifier ru.arvectum.qrdeviceqa.device. It has no App Group entitlement, no PacketTunnel and no networking entitlement. It never accesses the production app, Keychain, saved proxy profiles or live VPN.

QA compiles the exact production SharedCore, ProxyShareView and ProxyQRScanner source files, not a rewritten copy. Its proxy is strictly synthetic: qr-device-qa.invalid with test-only username/password.

On-device test: ProxyProfileSharing.deepLink -> ProxyShareQRCode.image -> real iPhone CIDetector decoding QR pixels -> ProxyProfileSharing.scannedSource -> ProxyImport.parse -> exact comparison of synthetic name, hostname, SOCKS5 protocol, username and Unicode/reserved-character password.

Device output was retrieved from its isolated Documents/qr-hardware-evidence.json using devicectl device copy from; no credentials appear in the evidence:

    result: PASS
    details: PASS: QR pixels decoded and profile matched on hardware
    device: iPhone
    os_version: 27.2
    bundle_id: ru.arvectum.qrdeviceqa.device
    date: 2026-11-04T11:46:38Z

Signed iPhoneOS QA build, install, launch, isolated app container read and read-only post-test production APL version verification: all PASS. Three isolation source-contract tests PASS.

## Explicit limitations

The signed physical Xcode UI test runner launched but XCTest did not initialize: XCTFuture Code=1000, Timed out while enabling automation mode. UI assertions did not run; this does not invalidate the separate in-app hardware QR pixel/code/parse PASS result.

Not yet verified on physical hardware: actual second-screen camera scan, Apple share-sheet user interaction, AirDrop/Messages, VoiceOver, import persistence in production APL or two-iPhone end-to-end transfer. These need functioning physical UI automation and/or human camera positioning. The earlier signed iPhone 13 Simulator sender UI test passed 1/1 but is not a real-device substitute.

Do not infer that an App Store 0.1.41 to 0.2.0 Keychain migration was tested. The production installation and live VPN were deliberately never replaced or reconfigured.

## Reproduction

The isolated QA XcodeGen spec, real source references and tests are in mobile/ios/HardwareQA/QRDeviceQA. Build/sign only the independent QA bundle for a paired developer-mode iPhone, launch it, and read the non-sensitive PASS/FAIL JSON from its own app data container. Never install, uninstall or reset the production APL bundle to perform this test. A complete Apple release still needs the distinct physical user-journey gates above.
