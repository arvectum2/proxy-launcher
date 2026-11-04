# APL iOS: share a saved proxy profile by QR (4 November 2026)

## User journey

1. Each profile row has an explicit Share button (hidden in bulk-edit mode).
2. Before touching Keychain, show consent: the QR/link contains proxy address, username and password **in plaintext**. Anybody scanning the QR can copy credentials. Share only with someone you trust.
3. Only after Show QR does APL read that profile's secret from Keychain and generate an in-memory QR for the registered app import deep link. White quiet zone is embedded in the exported QR.
4. System Apple Share Sheet exports both QR image and app import link. There is no APL sharing server, API call, clipboard copy or analytics event.
5. The receiver scans with the native camera or in-app QR scanner. Both lead to the existing import preview with **one explicit Import** action. Existing duplicate detection, saved active profile, VPN state and lack of silent auto-connect remain unchanged.

## Wire format and security

- The URI is arvectum-proxy://import?data=..., using a percent-encoded canonical HTTP/HTTPS/SOCKS5 proxy URI with optional username, password and profile name fragment. AUTO is not a transferable upstream scheme.
- URLComponents percent-encodes reserved characters, IPv6 and Unicode; the sender validates exact round-trip through the receiver parser before generating. 1800-byte QR URI cap.
- Fixes an existing importer issue: URLComponents.user/password/fragment are already percent-decoded; the previous additional removingPercentEncoding damaged percent-containing credentials.
- Generated QR is not stored to App Group, UserDefaults or logs; sheet dismissal releases its view state. Third-party share recipients may independently retain the image/link. Rotating upstream credentials is the only reliable revocation after sharing.
- Seven new short UI strings are explicitly localized for 13 locales (ru, en, de, fr, es, it, pt, uk, ja, ko, zh-Hans, zh-Hant, tr). The other interface languages use an explicit English fallback. The original 64 release translation catalogs are unchanged; future native editorial review remains pending.

## Test evidence and gates

- Synthetic Core Swift tests: HTTP, HTTPS, SOCKS5, IPv6, Unicode, percent/reserved characters, registered link, malicious schemes and AUTO rejection.
- Python source contracts: explicit Keychain/consent boundary, no silent writes, white QR quiet zone and platform share sheet, 64 frozen locale catalogs.
- App + PacketTunnel ARM64 Simulator unsigned build.
- Isolated disposable iOS Simulator UI consent -> visible QR -> dismiss flow (never taps third-party share).
- **Remaining device gate:** real iPhone-to-iPhone QR scanning, system Camera/AirDrop/Messages delivery, VoiceOver, actual profile import and unchanged active VPN; no owner production device or paid proxy experimentation.

Source-only post-0.2.0 work. The already submitted iOS 0.2.0(48) App Review is untouched; no new App Store version or production VPN change.
