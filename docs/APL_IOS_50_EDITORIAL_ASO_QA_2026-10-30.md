# APL iOS — multilingual editorial + App Store ASO QA (2026-10-30)

## Verified scope and delivery

- **50 iOS app languages / 7,750 UI entries**. All 155 keys in every `Localizable.strings`; edited and verified using ChatGPT multilingual reasoning with an automated consistency sweep, not by an independently hired human linguist.
- **47 Apple App Store localization variants** derived from **42** supported languages in the app. Regional variants are independently authored for English (US, UK, AU, CA), French (France, Canada) and Spanish (Spain, Mexico).
- ASO contains local `name`, `subtitle`, `description`, `keywords`, `promotionalText`, `whatsNew`, URL fields and copy for feature screenshots. Each variant has seven export-ready metadata files, plus JSON source; `build_metadata.py` works offline.
- **94 actual iPhone screenshots**: two screens per App Store locale, created by iOS Simulator with its actual user-visible UI (setup guide and explanatory page). JPEG with no alpha, 1206×2622, supported by Apple as Dynamic Island medium iPhone.
- Fixed a genuine **wordmark visibility bug**: standalone PNG was present in bundle but SwiftUI named-image lookup could render a blank background; now explicitly load the bundled UIImage with a safe fallback at the three original placements.
- Corrected high-impact routing exception terminology in **17 languages** and disconnect actions in **3** (18 distinct locales), plus original `host:port` format in 8 locales. Specific defects included words meaning unrelated concepts such as boycotts, evictions, expenses or service outages.
- Preserved App Store Connect live state, published build, account/privacy metadata and disabled Watchdog; no API writes or new release submission.

## Validation

- Localized ASO metadata: all 47 exact Apple locales; name/subtitle ≤30 characters, promotional text ≤170, description ≤4000, keywords **≤100 UTF-8 bytes**; no empty fields, region codes and screenshots linked.
- iOS strings: all 50 `plutil` passes and exact lookup key/placeholder parity, no unintentional long English fallback in non-English catalogs, no Unicode replacement characters.
- Signed Apple Distribution iOS archive contains 50 `.lproj` and PacketTunnel; verified with `codesign --verify --deep --strict`. Exported IPA locally for packaging QA; not uploaded.
- Simulator visual inspection of English/Hausa/Amharic/Serbian/Hebrew and newly sampled Arabic/Hindi/Japanese; text alignment, RTL, font coverage and buttons checked at standard text size. The screenshot campaign exercises the first-use and privacy UI across 42 unique Apple-ASO languages.
- Final local regression: **30 iOS and localization tests passed**, 50/50 Apple `plutil` lint, all 47 ASO metadata variants within Apple character/UTF-8-byte limits, all **94** screenshots validated as 1206×2622 opaque JPEGs, and automated 50-language lexical audit reported zero unresolved source/key/format errors.
- Final locally signed archive: 50 iOS languages, one PacketTunnel extension, `codesign --deep --strict` passed; **IPA EXPORT SUCCEEDED**. IPA SHA-256: `cb36676ee4dc760edbff62cd5af7a1189e00e57cdcadfad6437234c37cb59804`.
- Local asset and regression tests: `tests/test_ios_aso_editorial.py`, `tests/test_ios_aso_screenshots.py`, `tests/test_ios_release50_localization.py`, and existing iOS onboarding/RTL tests.

## iOS language-by-language review matrix

| iOS | Strings | Apple ASO | Editorial change this pass |
|---|---:|---|---|
| `en` | 155 | en-US, en-GB, en-AU, en-CA | Source / technical / formatting audit |
| `ru` | 155 | ru | Source / technical / formatting audit |
| `es` | 155 | es-ES, es-MX | Terms / UI |
| `fr` | 155 | fr-FR, fr-CA | Terms / UI |
| `de` | 155 | de-DE | Terms / UI |
| `it` | 155 | it | Source / technical / formatting audit |
| `pt-BR` | 155 | pt-BR | Source / technical / formatting audit |
| `pt-PT` | 155 | pt-PT | Source / technical / formatting audit |
| `ja` | 155 | ja | Terms / UI |
| `ko` | 155 | ko | Terms / UI |
| `zh-Hans` | 155 | zh-Hans | Terms / UI |
| `zh-Hant` | 155 | zh-Hant | Terms / UI |
| `fa` | 155 | Apple fallback | Source / technical / formatting audit |
| `nl` | 155 | nl-NL | Terms / UI |
| `id` | 155 | id | Terms / UI |
| `tr` | 155 | tr | Source / technical / formatting audit |
| `hi` | 155 | hi | Terms / UI |
| `ar` | 155 | ar-SA | Source / technical / formatting audit |
| `vi` | 155 | vi | Source / technical / formatting audit |
| `pl` | 155 | pl | Terms / UI |
| `th` | 155 | th | Source / technical / formatting audit |
| `ur` | 155 | ur-PK | Terms / UI |
| `bn` | 155 | bn-BD | Terms / UI |
| `pa` | 155 | pa-IN | Terms / UI |
| `ta` | 155 | ta-IN | Source / technical / formatting audit |
| `te` | 155 | te-IN | Source / technical / formatting audit |
| `mr` | 155 | mr-IN | Terms / UI |
| `gu` | 155 | gu-IN | Terms / UI |
| `kn` | 155 | kn-IN | Terms / UI |
| `ml` | 155 | ml-IN | Source / technical / formatting audit |
| `uz` | 155 | Apple fallback | Source / technical / formatting audit |
| `ms` | 155 | ms | Source / technical / formatting audit |
| `fil` | 155 | Apple fallback | Source / technical / formatting audit |
| `sw` | 155 | Apple fallback | Source / technical / formatting audit |
| `ro` | 155 | ro | Terms / UI |
| `hu` | 155 | hu | Source / technical / formatting audit |
| `cs` | 155 | cs | Terms / UI |
| `sk` | 155 | sk | Terms / UI |
| `el` | 155 | el | Terms / UI |
| `he` | 155 | he | Terms / UI |
| `ha` | 155 | Apple fallback | Source / technical / formatting audit |
| `am` | 155 | Apple fallback | Source / technical / formatting audit |
| `sv` | 155 | sv | Source / technical / formatting audit |
| `da` | 155 | da | Source / technical / formatting audit |
| `fi` | 155 | fi | Source / technical / formatting audit |
| `nb` | 155 | no | Source / technical / formatting audit |
| `bg` | 155 | Apple fallback | Source / technical / formatting audit |
| `sr` | 155 | Apple fallback | Source / technical / formatting audit |
| `hr` | 155 | hr | Source / technical / formatting audit |
| `ca` | 155 | ca | Source / technical / formatting audit |

## Release handoff

ASO JSON: `mobile/ios/ASO/localizations.json`; per-market copy: `mobile/ios/ASO/metadata/<locale>/`; screenshots: `mobile/ios/ASO/screenshots/<locale>/`.
Only submit metadata with an editable new App Store version. The independent human native-language signoff, broader device-size accessibility testing, and ASO keyword performance measurement (search volume/rank) have **not** been performed; they must not be represented as completed. This package is a complete, checked editorial and image input to publication, not a claim of external certifications or a guarantee of App Store search placement.
Apple specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations ; https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/ ; https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/
