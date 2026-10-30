# Arvectum Proxy Launcher — iOS App Store localization package

This directory contains **47 Apple-supported App Store localization records** that map to **42 of the 50 shipped iOS UI languages**, with genuine regional variants for English, French and Spanish. It does **not** represent 47 separate binary languages; the iOS app itself has **50** complete source catalogs.

## Editorial sources and export files

- `localized-copy.psv` — ChatGPT-authored localization and ASO copy, including native-language terminology, descriptions, feature statements and search words. Regional variants have independent keyword choices.
- `build_metadata.py` — deterministic generator and Apple hard-limit validator; **no network or App Store Connect write operations**. Run `python3.14 mobile/ios/ASO/build_metadata.py` from the repository root after changing source copy.
- `localizations.json` — canonical JSON payload for an eventual authorized App Store Connect import. App-level `name` and `subtitle` map to `appInfoLocalizations`; `description`, `keywords`, `promotionalText`, `whatsNew`, `supportUrl` and `marketingUrl` map to `appStoreVersionLocalizations`. The existing App Store privacy declaration is outside this payload.
- `metadata/<apple-locale>/` — per-locale `name.txt`, `subtitle.txt`, `description.txt`, `keywords.txt`, `promotional_text.txt`, `release_notes.txt` and `screenshot_copy.json`. UTF-8 everywhere.
- `screenshots/<apple-locale>/` — two **actual iOS Simulator screenshots** per locale, no fabricated connection states: `01-first-connection.jpg` and `02-local-privacy.jpg`. These show the app's genuine onboarding and explanatory UI. They are not hypothetical mockups. Region variants that share the same iOS UI language reuse the same native screenshots; their metadata remains region-specific.

## Apple constraints and mapping

- Product name at most 30 characters; local subtitle at most 30 characters; promotional text at most 170; description at most 4000; keywords at most **100 bytes in UTF-8** (not 100 Unicode characters).
- Current package supports 47 locales and the official BCP-47/API variants, including `bn-BD`, `gu-IN`, `kn-IN`, `ml-IN`, `mr-IN`, `pa-IN`, `ta-IN`, `te-IN`, `ur-PK`, `ar-SA`, `no` (for app `nb`) and regional English/French/Spanish versions.
- Apple currently doesn't expose separate App Store listing language variants for 8 existing iOS UI languages: Persian `fa`, Uzbek `uz`, Filipino `fil`, Swahili `sw`, Hausa `ha`, Amharic `am`, Bulgarian `bg` and Serbian `sr`. These languages **remain localized inside the iOS binary** and receive Apple's supported listing fallback. There is no invented non-Apple ASO locale.
- Screenshot originals are 1206 × 2622 (Apple-supported Dynamic Island medium iPhone portrait size) and stored as opaque JPEGs. No App Store Connect upload performed.
- All claims focus on verified functions in the iOS source: self-configured HTTP / HTTPS CONNECT / SOCKS5 connections, profiles, fallback/priority, direct website exclusions, optional iOS Shortcuts user-created automations and locally held credentials. App name is consistent for all markets.

## Release workflow

1. Run the metadata generator and `python3.14 -m pytest -q tests/test_ios_aso_editorial.py tests/test_ios_aso_screenshots.py`.
2. Inspect screenshot text overflow, RTL and native Shortcuts terms at all large accessibility sizes, then obtain an independent human-language review if required by the release process. The current translations are authored and edited by ChatGPT; no third-party human linguist has been represented as consulted.
3. For a **new, editable** iOS version in App Store Connect, import localizations and screenshots only after release authorization. Keep the live card and privacy information untouched until specifically instructed.
4. If editing screenshots, preserve actual application content. All visible UI must reflect real features; do not invent successful proxy connections or add product claims unsupported by the app.

**Sources**: Apple App Store localization and screenshot specifications, and App Store Connect metadata property limits (2026-10-30). See `docs/APL_IOS_50_EDITORIAL_ASO_QA_2026-10-30.md` for local test evidence.
