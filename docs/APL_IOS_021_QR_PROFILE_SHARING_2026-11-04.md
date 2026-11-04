# iOS roadmap — one-profile QR sharing (4 November 2026)

## User journey

Sender: open Profiles → tap the per-profile Share icon → APL reads that one profile's saved Keychain password on explicit interaction → generate a high-contrast QR locally, display it and optionally open the standard Apple share sheet to send the QR image plus a matching import link.

Receiver: open QR with APL's built-in camera scanner or accept the app-registered arvectum-proxy://import?data=... deep link. The existing import preview displays one candidate; pressing Import profiles **once** adds a new profile. Existing duplicate filtering, atomic rollback, no replacement of current selection and no unexpected VPN reconnect are preserved.

No external server, cloud gateway, analytics, proxy account registration or special QR service is involved. The sender's purchased upstream login/password are included in an offline transferable QR only by an explicit share tap.

## Portable format and safety

- Versioned APL1 format: apl1.<unpadded base64url JSON>, with version, name, host, port, ProxyType, username and password. The outer APL import deep link is percent-encoded by URLComponents.
- All four ProxyType values are preserved, including AUTO. Unlike ad-hoc HTTP proxy links, the versioned JSON preserves literal percent signs, @, colon, Unicode, IPv6 and embedded punctuation without accidental double URL decoding.
- One profile only. QR payload is bounded to 1400 UTF-8 bytes. Decoder limits names, host, login and password; validates the endpoint with the existing strict ProxyImport.item authority checks, rejects unsupported versions, malformed base64 and duplicated data query items.
- Existing plain HTTP/HTTPS/SOCKS5, CSV, XML, IP:port and previous deep links remain backward compatible.
- The QR/image and link are held only in the Share view state; no password copied to clipboard, stored to UserDefaults or added to logs. The view shows an explicit warning that QR may contain credentials. System sharing transmits these values only at the sender's command. Treat a sent QR as equivalent to disclosing the upstream password; it is not revocable by the app without changing upstream credentials.
- The profile library's bulk-selection mode does not expose individual Share buttons.

## Localization gate

User-facing Share strings have Russian, English and twelve curated major-market translations; all other supported iOS languages display a non-Russian English fallback. The existing Close button is provided by the 64-language import UI. This is a **source-only candidate**, not localization-certified in all 64 languages. Complete human/native editorial checking and 64-language coverage before public iOS App Store release.

## Verification

- Five Swift Core QR codec tests, covering HTTP/HTTPS/SOCKS5/AUTO, Unicode, percent escapes, IPv6, malformed input, oversized credentials and legacy/duplicate import compatibility: PASS.
- Full Swift Core after feature: 151/151 PASS; iOS source Python baseline 104 tests (1 skipped) PASS.
- Four new source contract tests check explicit share action, on-demand Keychain read, on-device CoreImage, Apple share sheet, import integration and English fallback.
- XcodeGen re-generated the tracked project deterministically: 14 additional lines registering the new Core and App Swift files (source manifest unchanged).
- Full ARM64 Simulator app + PacketTunnel build: PASS after deterministic XcodeGen regeneration.
- Disposable iPhone 13 / iOS 27.0 UI XCTest compilation after registering the production QR codec in the UI-test target: source compiles, but XCTest runner launch became unresponsive under Xcode 27.1. The isolated test was terminated without a valid XCTest result and temporary simulators were removed. The UI test therefore is **UNVERIFIED**, not a pass; it requires independent rerun before release.
- No real iPhone, purchased proxy, Apple review 0.2.0, production VPN or advertising settings were changed.

## Unfinished hardware/release gates

1. Physical distinct-device test: original iPhone camera and APL in-app QR scanner open the deep link and add a profile with a single explicit import action. Do not use owner's paid proxies for this test; use a disposable upstream with renewable credentials. Confirm no automatic VPN change.
2. Security QA: revocation plan for QR disclosure, screenshot / lockscreen leakage, AirDrop, Messages, keychain access failures, app backgrounding and closed sheet memory lifecycle.
3. Translation editorial and actual App Store signing/release decision. No new production version or submission without those gates.
