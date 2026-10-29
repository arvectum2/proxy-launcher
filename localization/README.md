# APL localization — Core-40 source coverage

The source baseline follows the first 12 Arvectum Tools Core *source* locales; Persian (`fa`), listed as tier 2 in the Core 50-language registry, is added as a fully populated priority language by direct owner request. This is **40**, not all 50 target languages.

`en`, `ru`, `es`, `fr`, `de`, `it`, `pt-BR`, `pt-PT`, `ja`, `ko`, `zh-Hans`, `zh-Hant`, **`fa` (فارسی)**, **`nl`, `id`, `tr`**, **`hi`, `ar`, `vi`, `pl`, `th`**, **`ur`, `bn`, `pa`, `ta`, `te`**, **`mr`, `gu`, `kn`, `ml`, `uz`**, **`ms`, `fil`, `sw`, `ro`, `hu`**, **`cs`, `sk`, `el`, `he`**.

- iOS: localized UI, setup, privacy and errors via `mobile/ios/Resources/*.lproj/Localizable.strings`; the app's language picker supports all 40 source languages plus system default. No production Apple version or submission is modified.
- Android: standard resource folders, automatic Android locale selection, and display messages are localized; internal Russian routing/status protocol literals remain unchanged to protect behavior.
- Desktop: Tk labels, dialogs and status strings via embedded `desktop_i18n.py`; follows OS locale with `APL_UI_LANGUAGE` developer override. Networking and proxy configuration are not locale-dependent.

**Stage (2026-10-29):** source-complete catalogs have completed a model-assisted technical/editorial correction pass, including cross-platform terminology, safety and error messages; **425 locale values changed** with 28 reviewed source-keyed glossary entries. Automated review covers the 12-language, 5424-entry corpus, but this is **not** an independent native-speaker sign-off. Dynamic text overflow, voice accessibility, device/simulator screenshots, consent truthfulness and App Store release approval remain outstanding. Do not mass-enable the remaining 10 target languages as empty/English catalogs. Preserve existing App Store Connect privacy declaration and review state; do not upload a new build without a separate release instruction.

Run `python3 -m pytest -q tests/test_core12_localization.py` and the platform-specific build/compile validation before release. UI resources are bundled in the regular target builds (iOS xcodegen and Android Gradle). Desktop catalogs are Python source to avoid external JSON data files in PyInstaller bundles.

## Second editorial sweep + Persian (29 Oct 2026)

Added a second copyediting pass on the original 12 languages (67 further complete onboarding/automations/connection-mode corrections), plus complete 452-entry Persian source catalog. iOS and Android use native RTL; desktop uses right-justified Tk copy rather than complete grid mirroring. Details: `docs/APL_CORE13_PERSIAN_EDITORIAL_QA_2026-10-29.md`. Do not ship RTL layouts without device UI approval.

## Core-16: Dutch, Indonesian, Turkish

Added 1356 new source UI translations across the three platforms, bringing the catalog to 7232 entries. Language selection includes NL/ID/TR. Manual source copyediting covers 54 long UI instructions, 21 high-risk recovery messages, plus 28 standardized technical terms. See `docs/APL_CORE16_LOCALIZATION_QA_2026-10-29.md`. Neither an App Store release nor independent human native-speaker approval is claimed.

## Core-21: hi, ar, vi, pl, th (29 Oct 2026)

Five complete source catalogs for iOS, Android and desktop (2260 additional UI values). Editorial edits cover 80 longer setup/system messages, five precise network-recovery instructions and five additional language glossaries of 28 core terms. Native Arabic RTL is supported in SwiftUI and Android; IP/port input remains LTR. See `docs/APL_CORE21_LOCALIZATION_QA_2026-10-29.md` for validation and physical-device QA gates.

## Core-26: Urdu, Bengali, Punjabi (Gurmukhi), Tamil, Telugu

Five complete locale catalogs added for iOS, Android and desktop (2260 strings). Urdu RTL is enabled across relevant UI frameworks; Punjabi Gurmukhi has a script-specific Android qualifier. 80 high-impact setup/automation help texts and 20 diagnostic/network recovery warnings copyedited. Full validation: `docs/APL_CORE26_LOCALIZATION_QA_2026-10-29.md`. Independent native editorial/physical accessibility QA remains before release.

## Core-31: Marathi, Gujarati, Kannada, Malayalam and Uzbek (Latin)

Five complete source catalogs on iOS, Android and desktop (2260 new values), 80 long setup/automation explanations and 20 critical desktop warnings reviewed, 28 glossary terms per new language. Script-qualified Android Uzbek `values-b+uz+Latn`, with explicit Cyrillic exclusion on iOS/desktop. Validation and remaining native-device QA: `docs/APL_CORE31_LOCALIZATION_QA_2026-10-29.md`.

## Core-36: Malay, Filipino, Swahili, Romanian and Hungarian

Five complete 155 iOS / 104 Android / 193 desktop catalogs (+2260 UI source values). Editorial revisions cover 80 onboarding and automation instructions and 20 critical network diagnostics/recovery warnings, with 28 standardized terms per language. Now 36/50 source languages; see `docs/APL_LOCALIZATION_COVERAGE_2026-10-29.md` for statuses and `docs/APL_CORE36_LOCALIZATION_QA_2026-10-29.md` for verification. Native-speaker and physical-device QA are separate release gates.

## Core-40: Czech, Slovak, Greek and Hebrew

Four full source catalogs (1808 values) with Hebrew RTL; edited 64 high-impact instructions, 16 desktop safety warnings, and 28 technical terms per language. All Tier-2 languages are now complete in source. See `docs/APL_CORE40_LOCALIZATION_QA_2026-10-29.md`.
