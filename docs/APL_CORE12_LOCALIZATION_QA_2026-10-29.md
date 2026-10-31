# APL — Core-12 locale source rollout and validation (2026-10-29)

## Scope and source authority

Canonical APL repo: `arvectum2/proxy-launcher`; based on `origin/main` at `179d74cf0a68b23e63dae77b78eab60721c7e328`. Source registry: Arvectum Tools `core/localization/portfolio-locales.json`. Implemented: `en, ru, es, fr, de, it, pt-BR, pt-PT, ja, ko, zh-Hans, zh-Hant`; `nl` not yet complete across Arvectum Tools Core portfolio. No other target languages enabled.

* iOS: 12 matching catalog files, 155 keys per locale, language picker with system selection, correct pt/zh language variants, no ads/privacy/backend/Info.plist edits. XcodeGen project updated to include 12 resources.
* Android: 12 XML catalogs (including RU default), 95 distinct static UI phrases and seven dynamic formatting keys. `MainActivity` displays localized text through Android resources; traffic/back-end protocol strings unchanged. Both Public and Private flavor compilers built.
* Desktop (macOS/Windows/Linux): 193 distinct Russian-keyed UI translations per locale embedded in `desktop_i18n.py` and used by Tk view/dialogs. Locale detection via OS, optionally overridden for testing with `APL_UI_LANGUAGE`. Keycode/keysyms and backend data remain nonlocalized.

## Verified QA evidence

- `plutil -lint` for 12 `.lproj/Localizable.strings` — PASS, all keys exact and nonempty.
- `xcrun swiftc -typecheck` for iOS `AppLocalization.swift` — PASS.
- iOS **unsigned UI-only** iPhone Simulator target built with `xcodebuild` — `BUILD SUCCEEDED`, all 12 `.lproj` directories physically present in compiled bundle. Full PacketTunnel target not built because patched tun2proxy XCFramework absent in the isolated source worktree. **Not an App Store archive or a VPN hardware functional test.**
- Android `gradle :app:compilePublicDebugKotlin :app:compilePrivateDebugKotlin` — `BUILD SUCCESSFUL` (JDK 17 / local Android SDK).
- Android `gradle :app:testPublicDebugUnitTest :app:testPrivateDebugUnitTest` — `BUILD SUCCESSFUL`.
- Python source parity `tests/test_core12_localization.py` — 6/6 PASS; `proxy_gui.py`, `linux_gui.py`, `desktop_i18n.py` compiled.
- Focused desktop: 55/55 PASS each for system EN, explicit RU, ES and JA.
- Full Python suite after updating locale-aware UI contracts: **1281 PASS, 1 skipped, 3 FAIL** on Windows App Control scripts/runbook contract tests. Identical 3 failures reproduced against untouched base `origin/main` (179d74cf) at `/tmp/apl-core12-baseline-check` (3/3 failed); these tests and their underlying code/docs were not changed as part of localization. Scoped full suite excluding those preexisting failures may be reported separately.
- `git diff --check` — PASS.

## Known limits and release gate

Automated initial translation only. Human linguistic editing for privacy/security/consent and UX, real device/simulator font/wrapping tests, VoiceOver, accessibility and screenshot review remain **PENDING**. The translated catalog's structural correctness is not equivalent to editorial approval. No new Store metadata locales or region-specific screenshots were uploaded; **App Store Connect privacy disclosure and the already-submitted review build remain untouched**. Changes belong only to a future release after user approval. The three unrelated preexisting Windows security test failures remain outside this task and must be handled in a separate maintenance workstream.
