# APL iOS 0.1.38 build 42 — theme and Arvectum.com metadata

Status: App Store Connect version created on 2026-10-27; submission and public release require independent validation.

## Changelog
- Settings → Appearance provides System / Light / Dark theme modes, persisted via local AppStorage.
- System is the default and follows dynamic iOS appearance changes; light appearance has a dedicated semantic palette for text/background/buttons; dark palette remains the established Arvectum brand appearance.
- App Store Support URL and Marketing (Developer Website) URL set to `https://arvectum.com/` in `ru` and `en-US`. These are App Store version **metadata** changes, not VPN/PacketTunnel changes.
- No advertising SDK, analytics or user-traffic changes introduced.

## Live Apple API evidence
- Existing live `0.1.37` (build 41): READY_FOR_SALE, currently points to GitHub, remains unchanged.
- New version `0.1.38`: App Store Connect id `2f7d4c38-ff0c-4ca5-81c5-6bfeeab768f6`, `PREPARE_FOR_SUBMISSION`, manual release type.
- `ru` localization id `60315bd2-dcda-48e1-84d3-2306bfa3cde7`: both `marketingUrl` and `supportUrl` PATCH HTTP 200; subsequent GET confirmed `https://arvectum.com/`.
- `en-US` localization id `72f4574f-e633-430d-b13f-0d2df98d9c5f`: same PATCH and GET verified.
- `https://arvectum.com/app-ads.txt` publicly accessible; Yandex RСЯ verification is only expected after the **public** App Store Developer Website URL points to arvectum.com.

## Release acceptance
- Swift package tests: PASS on Xcode 27.1 Mac mini.
- Unsigned iPhone Release build: PASS. Pre-existing Swift 6 concurrency warnings in ProxyProbe and TLSProxyRelay do not fail Swift 5.9 build.
- Signed Release archive, IPA upload, App Review submission, and public Apple card verification: track separately; do not mark complete until proven by Apple API.

No advertising is included: Apple VPN guideline 5.4/privacy review still applies to future ads.
