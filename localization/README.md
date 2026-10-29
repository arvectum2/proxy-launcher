# APL localization — Core baseline (12 source locales)

The source language baseline is synchronized with `arvectum-tools/core/localization/portfolio-locales.json` (the first 12 approved *source* locales, not the 50-language future target).

`en`, `ru`, `es`, `fr`, `de`, `it`, `pt-BR`, `pt-PT`, `ja`, `ko`, `zh-Hans`, `zh-Hant`.

- iOS: localized UI, setup, privacy and errors via `mobile/ios/Resources/*.lproj/Localizable.strings`; the app's language picker supports all 12 plus iOS language. No production Apple version or submission is modified.
- Android: standard resource folders, automatic Android locale selection, and display messages are localized; internal Russian routing/status protocol literals remain unchanged to protect behavior.
- Desktop: Tk labels, dialogs and status strings via embedded `desktop_i18n.py`; follows OS locale with `APL_UI_LANGUAGE` developer override. Networking and proxy configuration are not locale-dependent.

**Stage (2026-10-29):** source-complete catalogs have completed a model-assisted technical/editorial correction pass, including cross-platform terminology, safety and error messages; **425 locale values changed** with 28 reviewed source-keyed glossary entries. Automated review covers the 12-language, 5424-entry corpus, but this is **not** an independent native-speaker sign-off. Dynamic text overflow, voice accessibility, device/simulator screenshots, consent truthfulness and App Store release approval remain outstanding. Do not mass-enable the remaining 38 target languages as empty/English catalogs. Preserve existing App Store Connect privacy declaration and review state; do not upload a new build without a separate release instruction.

Run `python3 -m pytest -q tests/test_core12_localization.py` and the platform-specific build/compile validation before release. UI resources are bundled in the regular target builds (iOS xcodegen and Android Gradle). Desktop catalogs are Python source to avoid external JSON data files in PyInstaller bundles.
