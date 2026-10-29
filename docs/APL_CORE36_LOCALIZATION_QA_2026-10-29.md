# APL Core-36 — ms, fil, sw, ro, hu

Date: 29 October 2026. Scope is source translation in PR #272, not an Apple build submission, App Store Connect metadata/privacy edit or watchdog change.

## Complete source catalogs

- Added Malay, Filipino, Swahili, Romanian and Hungarian. Each includes **155 iOS .strings, 104 Android XML, 193 desktop embedded string values**. New wave: **2260 UI values**. Total: **36 languages, 16272 source values**.
- iOS native language chooser and OS matching; Android values-ms/fil/sw/ro/hu; desktop OS locale matching and APL_UI_LANGUAGE override. Existing 31 languages and RTL support remain unchanged.
- Initial translations used a batched machine translation service with protected technical markers; 80 long setup/Shortcuts/exclusion/connection-mode instructions were manually rephrased (16 per language). Added 28 reviewed technical glossary entries in each language.
- Copyedited 20 desktop recovery and network-state warnings: exact restoration button name, mandatory diagnostics without automatic resets, preserving other programs settings and incomplete rollback. Preserved whitespace between concatenated GUI fragments.

## Verification

- 27 focused localization tests PASS, including complete keys, placeholders, branded app title, registry and safety-label matching.
- Full Python regression with APL_UI_LANGUAGE=ms: **1297 passed, 6 skipped, 3 inherited unrelated Windows tests deselected, 113 subtests passed**.
- iOS XcodeGen, Swift Simulator AppLocalization typecheck, 36 .strings plutil checks PASS; unsigned **UI-only** iOS Simulator **BUILD SUCCEEDED** with 36 bundled .lproj. A signed PacketTunnel release build was not made.
- Android Public/Private Kotlin compile and unit tests (JDK17 Gradle) **BUILD SUCCESSFUL**, 49 tasks.
- Git whitespace and format parity checks passed; no networking, PAC or production app release settings changed.

## Separate release QA

Machine-assisted translations with manually edited critical instructions are not independent professional native-speaker signoff. Test real devices for long labels, accessibility, iOS Shortcuts naming and network messages. No auto-merge or App Store Connect changes.
