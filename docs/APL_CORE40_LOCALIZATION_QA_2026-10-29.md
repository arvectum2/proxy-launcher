# APL Core-40 — cs, sk, el, he

29.10.2026. Four complete Tier-2 languages: Czech, Slovak, Greek, Hebrew. Each has 155 iOS, 104 Android and 193 desktop source strings (452 × 4 = 1808); 40 languages total, 18080 UI values. New catalogs are machine-assisted translations with 64 hand-edited critical setup/Shortcuts/connection/site-exclusion instructions, 16 desktop recovery/diagnostic network safety messages and 28 terminology entries per language.

Hebrew RTL added alongside fa/ar/ur in SwiftUI, and right-aligned text in Tk desktop. Android supports RTL; address, host and port inputs remain LTR. Android legacy Hebrew qualifier is `values-iw`. Other languages and routing unchanged.

## Verification

- 29 focused localization tests PASS, including complete 155/104/193 key/format parity and Hebrew RTL; inherited RTL assertions updated.
- Full Python regression APL_UI_LANGUAGE=he: 1299 passed, 6 skipped, 3 inherited unrelated Windows tests deselected, 113 subtests passed.
- iOS xcodegen, Swift simulator localization typecheck, 40 `.strings` plutil PASS; unsigned UI-only Simulator BUILD SUCCEEDED with 40 `.lproj`. Signed PacketTunnel archive was not built.
- Android JDK17 Gradle Public/Private Kotlin compile and unit tests BUILD SUCCESSFUL (49 tasks).
- Source validation and git diff --check PASS.

## Separate release requirements

Translations are not independently proofread by native speakers. Physical device tests of layout, Hebrew bidirectional URL/IP, VoiceOver/TalkBack, localized Shortcuts actions, and signed VPN distribution archive remain necessary. PR #272 is source-only; existing Apple submission, App Store Connect privacy and disabled watchdog unchanged.
