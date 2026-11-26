# APL-ANDROID-IMPORT-PREVIEW-20261126

## Scope
Single ordinary proxy URI or supplier notation pasted deliberately into an Android new-profile editor. This is the first independent APL-CONNECT-001 Android slice, based on iOS 0.3.0 import behavior. No native protocol, automatic clipboard, networking, subscription, QR or release change.

## Requirements
- A1: HTTP/HTTPS/SOCKS5 URI (socks5h/socks aliases), host:port or host:port:user:password, bracketed IPv6, explicit port.
- A2: Bounded one-entry input; reject unsupported schemes, invalid ports/hosts, query/path, malformed escaping and ambiguous credentials. No DNS resolution.
- A3: Preview only; user enters text and explicitly previews; editor fields populate without saving or changing current connection. Existing Save flow is the only persistence boundary.
- A4: No credential logging or errors echoing input; masked input and existing encrypted store; no persistence on cancel.
- A5: JVM tests with synthetic fixtures, Android build/lint and device/editor smoke when available. Do not equate parser tests with UI/network acceptance.
- A6: Keep existing version, signing and distribution. RuStore last known rejection 06.10.2026, rules 2.12/12.1. No resubmission or misrepresentation. Official rules reviewed 26.11: https://www.rustore.ru/help/developers/publishing-and-verifying-apps/requirement-apps ; distribution requires distinct resolution.
