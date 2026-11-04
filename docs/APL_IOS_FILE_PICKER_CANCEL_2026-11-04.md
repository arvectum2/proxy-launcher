# iOS: Files importer user cancellation is not a parse failure (4 Nov 2026)

## User-visible defect

Canceling the iOS system Files picker previously took the same
ProxyImportUX.error path as failed reading a proxy supplier file.
The UI could show a red error such as "Could not read the file"
even though the user explicitly tapped Cancel.

## Narrow fix

New pure SharedCore ProxyFilePickerCancellation checks BOTH the Cocoa
NSError domain and NSUserCancelledError. Only that well-defined user action
is silent. An NSError with the same numeric code in a different domain,
missing file, denied Files access, invalid UTF-8, malformed proxy or
oversized document is still reported as a bounded localized import error.

Files import still uses the preexisting bounded 256KB FileHandle reader,
security-scoped access release, explicit preview, deduplication, save
rollback and one bounded post-import scan. No changes to proxy storage,
VPN routing, credentials, PacketTunnel or Apple App Review.

## Verified locally on parent iOS integration

- 5 focused Swift Core tests PASS for user cancellation, Cocoa type bridge,
  same numeric code in another NSError domain and noncancel Cocoa
  filesystem errors.
- 3 focused source/privacy tests PASS; updated existing bounded-reader
  source contract to accept the equivalent safe error variable.
- Full Swift Core 176/176 PASS.
- Full iOS Python 171 tests run (one skipped), no failures.
- XcodeGen + unsigned ARM64 Simulator App+PacketTunnel BUILD PASS.
- Compiled app debug.dylib contains ProxyFilePickerCancellation classifier.
- Hardware Files picker tapping Cancel not physically exercised. Owner
  iPhone, macOS build, VPN, Keychain and Apple review unchanged.

Source work is intentionally based on the integrated iOS PR #337.
Parent integration PR #337 is merged at 268dfc6b (19/19 CI); task closure PR #338 at 384c2cba. Publish this follow-on change only with separate CI,
then verify an independent exact-head GitHub CI and merge.
