# iOS QR scanner — typed, localized AVFoundation failures (4 November 2026)

## Defect and fix

The QR scanner previously displayed unpredictable AVFoundation error descriptions
and determined when to show Camera Settings by comparing the Russian text
of the error. This could leak system diagnostics in UI and made permission
recovery dependent on translation/wording.

New ProxyQRScannerFailure has five cases: permissionDenied,
cameraUnavailable, inputUnavailable, outputUnavailable and startFailed.
All map to four vetted ProxyImport.strings keys present in 64/64 UI locales.
ProxyImportView now localizes typed failures and shows the Settings CTA only
for permissionDenied, never by string comparison.

Camera startRunning() result is explicitly inspected; onReady is fired only
when running, else stable startFailed is delivered. Permission and camera
callbacks arriving after sheet dismissal are suppressed. No proxy credentials,
QR payloads, camera frames or underlying AVFoundation exception details are
logged or surfaced.

## Verification

- 6 focused source/locale contract tests PASS, all four error keys in 64/64
  localization catalogs.
- Full iOS Python: 139 tests, one skipped, no failures.
- Swift Core: 159/159 PASS.
- XcodeGen + unsigned ARM64 iOS Simulator App+PacketTunnel BUILD PASS.
- Independent unsigned ARM64 APLQRDeviceQA Simulator app with the production
  QR camera source BUILD PASS.
- No physical iPhone, user VPN/Keychain, production profiles, Apple submitted
  0.2.0(48), release version or PacketTunnel routing modifications.

This is a compiled-source and simulator QA result, not proof of camera
permission on physical hardware. Owner chose to test cross-iPhone QR transfer
after the first QR-containing App Store release, with fixes next version.
PR #314 FIN/CLOSE_WAIT remains DRAFT; PR #330 is separate.
