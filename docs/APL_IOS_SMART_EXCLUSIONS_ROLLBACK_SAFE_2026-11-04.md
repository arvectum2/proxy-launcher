# iOS — Privacy-safe Smart Exclusions rollback (4 November 2026)

## Defect

When a Smart Exclusions save triggered a VPN reconnect failure,
AppViewModel.saveExclusions correctly restored the previous manual rules
and related-domain graph, then optionally attempted to restore the
previously active VPN. However, three error paths displayed arbitrary
error.localizedDescription from underlying profile-store or
NetworkExtension errors. Such descriptions can contain filesystem paths,
proxy hostnames, internal network URLs or secret-bearing diagnostics.

The existing two rollback/reconnect recovery hints were already
translated in all 64 ProfileManagement catalogs but previously looked up
in generic Localizable and concatenated unsafe error text.

## Correction

- Save/validation errors are classified into finite, safe typed
  SiteExclusionSaveFailure cases (manual invalid address, unsupported
  wildcard, too many manual exclusions, related-domain invalid parent/
  child or graph limit, and unknown).
- Existing graph validation messages are translated from all 64
  SmartExclusions.strings catalogs.
- Manual input and unknown storage failures use accurate bounded Russian/
  English fallback, without echoing the original NSError.
- Known VPN/transport errors use existing safe ProxyFailureReason
  classifications and fixed recovery strings.
- Failed persistence rollback reports the pre-existing 64-language
  ProfileManagement hint with no native exception.
- Successfully restored exclusions but failed VPN reconnect reports the
  other pre-existing 64-language ProfileManagement hint plus a finite
  stable error code, not any host, account, path or NSError detail.

The transaction order is *unchanged*: normalize and validate, persist
new manual/graph rules, reconnect the previously active VPN, restore the
old manual/graph snapshot if activation failed, update in-memory
snapshots, and attempt VPN restoration only if it was active before.
No routes, excluded IP addresses, stored credentials, Keychain
operations, FileHandle code or PacketTunnel behavior were changed.

## Evidence

- 5 pure Swift unit tests PASS for every manual/graph reason, finite
  safe messages, adversarial NSError descriptions and unmodified
  normalizer behavior.
- 4 portable Python UI/transaction-order/source/64-locale tests PASS.
- Full iOS Swift Core **176/176 PASS**.
- Full iOS Python source/privacy/locale **172 tests, one skipped, no failures**.
- XcodeGen and unsigned ARM64 Simulator App+PacketTunnel **BUILD PASS**.
- Actual compiled app contains SiteExclusionSaveUX.failed symbol.
- No real iPhone/proxy/VPN/Keychain, macOS published source, Apple
  review, iCloud entitlements, native draft PR #314 or two-iPhone QR
  release acceptance were modified.

This validates the new source and simulator build; real user connection
recovery remains a separate hardware acceptance gate.
