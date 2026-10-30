# APL iOS — Home screen banner-safe 50-language UI/UX acceptance (30 October 2026)

## Scope and observed issue

The previous `ContentView.swift` rendered the iPhone Home through a **vertical `ScrollView`**, stacking two oversized cards (`80 pt` primary button, `18 pt` spacing, duplicate secondary actions), with no bounded region for a banner. Long translated strings could push the profile section below the viewport. This is corrected for **iOS Home only**; the scrollable Profiles/Activity/Settings screens and macOS Catalyst layout are not modified.

## Applied responsive UX fixes

- Replaced the iPhone Home `ScrollView` with a viewport-bounded `GeometryReader` and non-scrollable `VStack`; the native iPhone `TabView` remains visible. A bottom `Spacer` ensures the banner region stays above the bottom tab bar.
- Compact mode is selected when the available home height is below `680 pt`; a tighter compact mode applies below `510 pt`. The primary button stays visible and at least **56 pt** tall, while card padding, spacing and font sizes respond to available height.
- Long translated action/status labels use single-line fitting with a minimum scale; explanatory text uses a two-line limit in compact mode. The connection and proxy section headings are explicitly passed through `AppL10n.tr` for all 50 languages.
- Removed duplicate secondary **Add proxy** / **Manage profiles** buttons from the *compact* Home card. Add remains the large primary action when no profile exists; profile management remains available in the persistent Profiles tab. A configured profile retains its in-card selection menu with a **44-pt compact touch target** (the final 10 extra-large accessibility checks were rerun after this adjustment).
- QA-only simulated states (`empty`, `connecting`, `connected`) and measured frame rects are enabled by dedicated Debug launch arguments. **These test switches do not change the real VPN/controller state** and do not display a fake advertisement in release builds.
- The source repository currently has no actual iOS banner component to exercise live ad-network loading. Tests use a real SwiftUI footprint **90 pt** (normal) and **100 pt** (large-banner stress), positioned immediately above the tab bar. The same constrained footer area must be used when the real banner host is connected; this audit verifies layout geometry, not live ad SDK delivery.

## Acceptance results on iOS 27.0 Simulators

| Device / typography / appearance | Languages | States per language | Banner | Result |
|---|---:|---|---:|---|
| iPhone SE 3, standard text, light | 50 | No profile / Connected / Connecting | 90 pt | **150/150 pass** |
| iPhone 13 mini, standard text, light | 50 | Configured profile, connected | 90 pt | **50/50 pass** |
| iPhone 17 Pro Max, standard text, light | 50 | Configured profile, connected | 90 pt | **50/50 pass** |
| iPhone SE 2, accessibility-medium, dark | 50 | No profile / Connected | 100 pt | **100/100 pass** |
| iPhone SE 2, accessibility-extra-large, dark | 10 risk languages (DE/FI/FR/AR/HE/AM/HA/HI/JA/RU) | No profile / Connected | 100 pt | **20/20 pass** |
| **Total** | | | | **370/370 pass, zero frame overlaps or viewport overflows** |

The automated geometry probe reads actual SwiftUI frames for header, connection card, primary action, proxy card and banner from the running simulator. It rejects negative/overlapping card boundaries, horizontal overflow, cropped action button, and banner extending below the Home viewport. The **minimum measured vertical clearance between profile card and banner was 18 pt** (extra-large accessibility stress); minimum footer clearance inside Home viewport was **9 pt**. The tab bar lies *outside* that viewport and is not occluded.

RTL Arabic/Hebrew and scripts requiring broader fonts (Hindi, Amharic, Hausa, Chinese, Japanese, Thai, Indic languages) were included in the 50-language matrix; genuine simulator screenshots were reviewed for representative RTL, Cyrillic and long European labels. All 50 locales passed the runtime geometry check in every standard-test scenario. Accessibility-extra-large was sampled on 10 high-risk languages rather than the entire set.

## QA records and build evidence

- Per-language matrix committed as `docs/APL_IOS_HOME_BANNER_QA_MATRIX_2026-10-30.csv`: 50 rows, seven standard/accessibility-medium scenarios each.
- Full **370 frame traces** and representative actual simulator screenshots are retained on Mac mini SSD under `/Volumes/ArvectumSSD/Arvectum/releases/APL-iOS-0.1.41-46-rc-audit-20261030/qa-evidence/`; 438 evidence files in total (370 base JSON files, 50 screenshots, and 10 final-code extra-large accessibility JSON checks plus 8 screenshots). This does not include mockups or images intended for App Store listings.
- `tests/test_ios_home_banner_fit.py` asserts non-scroll Home, Debug-only QA creative, accessible actions and translated critical labels. `tests/test_ios_home_banner_qa_matrix.py` checks all 50 languages have successful results. The existing iOS onboarding localization source contract was updated to account for Debug-only status simulation while ensuring production still uses real `model.vpn.detail`.
- Fresh signed Apple Distribution **0.1.41 (46)** candidate with `50 .lproj` catalogs and `1 PacketTunnel` included in archive and IPA; see `candidate-manifest.json` in the SSD release directory. Archive and IPA were created with the existing isolated `build_release_041.py` and **not uploaded**.

## Release boundary

Only iOS Home UI, the Debug geometry probe and iOS-specific QA/tests/docs changed. No new Apple App Store version, App Store Connect edits, review withdrawal, privacy declaration, other platforms or watchdog modifications. The existing 0.1.40 remains in review. A future live banner integration should be tested at its actual SDK-reported adaptive size before shipment; this audit has deliberately reserved/tested a conservative 100-pt height.

## Final release artifact

Updated 0.1.41 (46) signed local archive and IPA after compact touch-target refinement: `/Volumes/ArvectumSSD/Arvectum/releases/APL-iOS-0.1.41-46-rc-audit-20261030/`. IPA SHA256: `a0b3e773f7f4be024c4b9e627251cb08799b5d923d9b52bf745dff65c6f27df2`, size 4,216,469 bytes, `codesign --verify --deep --strict` PASS; archive/IPA contain 50 iOS `.lproj` and one PacketTunnel. It supersedes the earlier unsigned-layout candidate and was **not uploaded** to Apple. The 10 highest-risk extra-large accessibility connected-state cases were rerun on this final build: **10/10 pass**. Total executed frame probes **380/380** including this final recheck.
