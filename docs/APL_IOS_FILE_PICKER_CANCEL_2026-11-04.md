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

## Verification and release integration

- 5 focused Swift Core tests PASS for user cancellation, Cocoa type bridge,
  same numeric code in another NSError domain and noncancel Cocoa
  filesystem errors.
- 3 focused source/privacy tests PASS; updated existing bounded-reader
  source contract to accept the equivalent safe error variable.
- Full Swift Core 176/176 PASS.
- Full iOS Python 171 tests run (one skipped), no failures.
- XcodeGen + unsigned ARM64 Simulator App+PacketTunnel BUILD PASS.
- Compiled app debug.dylib contains ProxyFilePickerCancellation classifier.
- Actual iOS Simulator Files picker choose -> Cancel -> return to importer with no error: **1/1 PASS**, 25.764 seconds. This was a temporary UI test with source restored after successful execution. An existing import preview UI smoke independently passed 1/1 (19.875 seconds).
- Following rebase over safe Exclusions PR #341, full Swift Core **181/181 PASS**, iOS Python **175 tests, one skipped**, ARM64 Simulator App+PacketTunnel and independent unsigned iPhoneOS/ARM64 App+PacketTunnel **BUILD PASS**.
- On a real iPhone 13 only existing public 0.1.41 UI was inspected via Mirroring. No replacement IPA, VPN reconnect, Keychain/profile modification or Apple submission.

Source PR #340 was rebased on integrated main with PR #337 and the independently merged safe Exclusions PR #341. GitHub CI for the exact head `20b6e337167dd1684c55059ca6c0b4d3f4bbc39f` eventually reached **25/25 SUCCESS**, following reruns of macOS hosted jobs cancelled before being assigned a runner. PR #340 **MERGED** at `478738d4f055401eb05db6a89397e59ccc8f8fba` on 5 November (Moscow time). No live iPhone or App Store release has been updated.
