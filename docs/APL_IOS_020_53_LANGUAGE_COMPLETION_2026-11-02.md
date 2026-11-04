# APL iOS 0.2.0 (48): Apple 50/50 App Store locales, 53 UI languages

Date: 2026-11-02. Source-only development in Draft PR #296; **iOS 0.1.41 remains on Apple review according to the owner and was not modified**. No App Store Connect API writes, app metadata changes, advertising/privacy labels, Apple upload, TestFlight or device VPN actions.

## Exact scope and result

- Official Apple App Store Connect supports **50 regional/language metadata locales** in an App Store operating in **175 regions**. 175 storefront territories are **not** 175 different supported metadata languages. Apple March 31, 2026 announced the expansion from 39 to 50. References: https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations and https://developer.apple.com/news/?id=97t4mt64 .
- Previous actual source state: 50 UI `.lproj`, 250 `.strings` files, 47/50 Apple ASO records and 94 screenshots. The exact three Apple missing codes were `or-IN`, `sl-SI`, `uk`; none of the app's 50 locales had `or`, `sl`, `uk`.
- New source: **53/53 iOS UI languages**, **265/265 `.strings` files** (5 tables, **344** entries per language), **50/50 Apple ASO metadata locales**, **100 real iOS Simulator screenshots** (two per Apple locale). AppStore-specific variants map to **45 distinct UI languages**, with supported fallbacks for the other eight iOS languages without dedicated App Store locales.
- Odia (`or`/`or-IN`), Slovenian (`sl`/`sl-SI`), Ukrainian (`uk`) added to `AppLanguage` picker, `ios-locales.json`, all five iOS tables, Xcode-generated `.pbxproj`, offline `localized-copy.psv`, `build_metadata.py`, `localizations.json`, seven output files per App Store locale and two JPEGs per locale. Product copy does **not** promise free proxy servers or changed VPN/privacy behavior.

## Editorial quality and remaining gate

The 1,032 new resource strings originate from **machine-assisted initial translation**, with subsequent targeted edits to user-facing terms (proxy/profiles, primary vs backup, direct exceptions vs bans, connect/disconnect, destructive actions), DNS/Network Extension/Packet Tunnel identifiers, URL examples (`http://`, `https://`, `socks5://`), `host:port`, Keychain, `gosuslugi.ru` and `gu-st.ru`, and numeric `%d` placeholders. Incorrect translated protocol spellings and several Odia UI terms were repaired; key/format parity and nonempty values are automated. **This is not an independently certified review by native speakers**; request focused human review of safety-critical Odia/Slovenian/Ukrainian copy before public publishing, especially Odia. The other 50 preexisting locales were not newly human reviewed. Apple metadata are *prepared offline*, not uploaded.

## Verification completed

- `scripts/ios_020_locale_audit.py`: **PASS** over all 53 languages, zero missing keys/format errors/unintended English fallback.
- `plutil -lint`: **265/265 PASS**.
- `tests/test_ios_53_apple_locale_coverage.py`: **2/2 PASS**. Existing UI/ASO/online-import mocking/localization compatibility suites: **36/36 PASS**, for **38/38 total targeted** tests (all offline, no real Apple writes).
- iOS Simulator `xcodebuild` (Xcode 27.1, `iOS 27.0` iPhone 16 Pro isolated simulator): **BUILD SUCCEEDED**, app bundle includes **53 `.lproj`**; project regenerated using `xcodegen`.
- Six final **genuine app UI screens** captured via `simctl launch` + `simctl io screenshot` for `or`, `sl`, `uk` in privacy disclosure and the first-use guide, converted to **1206×2622 opaque JPEG**. `tests/test_ios_aso_screenshots.py` validated all **100 images** with real JPEG SOF dimensions and distinct images in each locale pair; no fabricated successful proxy connection or mockup.
- Version stays **0.2.0 (48)** in sources. Historical Apple Distribution IPA created before these source/localization changes **does not contain the three new languages** and must be re-archived and re-signed before an owner-approved future submission.

## Explicit release/operations exclusions

No submitted Apple **0.1.41** version was withdrawn or edited. ASO importer only prepared offline 0.2 source data, and its regression tests verify fail-closed Apple review state. No changes to live ads/privacy disclosures, user's iPhone, Tailscale, Keychain, previously passing real VPN failover, the disabled Watchdog, or production proxy credentials. `PR #296` remains Draft pending separate release decision.

**Definition of Done:** source/bundle/metadata/screenshots/automated QA complete for all Apple-localizable catalog entries; independent human native copy review and future authorized Apple submission are *separate* open publication gates.
