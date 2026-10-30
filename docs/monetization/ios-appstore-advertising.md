# APL-IOS-ADS-001 — advertising and App Store compliance plan

Status: **Owner requested production RSYA banner enabled in source for iOS 0.1.39 (44); App Store upload/review not verified.**
Updated: 2026-10-28 (preserved #262 research; reconciled against merged #265)
Owner signal: >100 App Store downloads (owner report, not verified directly).
RSYA ownership: owner confirmed 2026-10-28 and supplied iOS banner unit `R-M-20288304-1`; dashboard-to-bundle provenance and regional availability remain to be independently verified.
Tracking: https://github.com/arvectum2/proxy-launcher/issues/261

## Stable app baseline

- Historical 0.1.36 / build 40 and 0.1.37 / build 41 are not the current public release. Apple public **single-app Lookup** on 28.10 confirmed **0.1.38** in **15 of 16 checked regions** (RU, US, GB, CA, AU, ES, MX, FR, DE, IT, PT, BR, JP, KR, TW); China (CN) returned `resultCount=0` by ID and bundle identifier, so no listing/version there was confirmed. Date in public result `2026-10-27T20:24:47Z`, minimum iOS 15.0. Public Lookup does not expose the installed build number, signed SHA or review history; 0.1.38 build 42 comes from source/release evidence in PR #265, not public API. [C18 read-only snapshot](apple-public-apl-ios-c18-20261028.json).
- iOS bundle: `ru.arvectum.proxylauncher.ios`, iOS 15+, native SwiftUI, `NEPacketTunnelProvider` in a separate extension.
- No advertising SDK was added by merged PR #265. Existing app disclosures promise no ads/analytics/tracking; preserve consistency until a separate privacy-compliant release is explicitly approved.
- `Config/AppPrivacy/PrivacyInfo.xcprivacy` sets `NSPrivacyTracking=false` and no collected data, and App Store privacy metadata has “Data Not Collected”. None of these statements may be carried forward unchanged if the ad integration changes real data behavior.
- The repository already has Android-specific Yandex App Open `R-M-20130429-1`. The project has a historical macOS advertising research note. **Do not assume any existing ad unit is registered for the iOS app.** This plan never connects to the Yandex partner account or creates an ad unit.

## Product rollout by gates

| Stage | Deliverable | Status |
| --- | --- | --- |
| P0 — Apple/legal | Document classification under App Review 5.4, SDK full data-flow/privacy analysis, and acceptable advertising method, obtaining written Apple clarification when necessary | **BLOCKED / REQUIRED BEFORE SDK** |
| P0 — RСЯ account | Owner confirmed ownership and supplied iOS banner `R-M-20288304-1`; verify exact bundle association, supported regions/creatives before activation | OWNER CONFIRMED; ACCOUNT DETAILS UNVERIFIED |
| P1 — UX | Choose an unobtrusive adaptive banner in Settings or Activity; no banners over connection controls; no interstitial/App Open in MVP | PRODUCT DIRECTION |
| P1 — Build (conditional) | Yandex Mobile Ads SDK 8.6.0 linked into iOS **main app only** on `feat/ios-rsya-banner-20261028`; Settings sticky banner, production ON by owner's explicit request, debug uses demo unit and explicit launch flag | SOURCE INTEGRATED; DEBUG/RELEASE UNSIGNED BUILDS PASS; PR PENDING |
| P1 — Privacy/ASO | Update policy, onboarding, App Privacy, privacy manifest, age rating/creative reporting, ATT decision, localized listing/links | NOT STARTED |
| P1 — QA/release | CI + Xcode no-sign build, real-iPhone VPN smoke, ad request/no-fill/offline, accessibility, network egress/privacy audit, TestFlight, App Review, human release decision | NOT STARTED |

## Why Apple guideline 5.4 is a stop gate

Official App Review Guidelines 5.4: applications offering VPN services may not sell, use, or disclose to third parties any user data for any purpose, and must commit to that in their privacy policy. APL is marketed/reviewed as a network utility using Apple's VPN/packet tunnel APIs, so compliance review is mandatory. Apple 2.5.18 additionally restricts advertising to the main app binary (not extensions) and requires appropriate ads, visible closing controls for interruptive ads and reporting of inappropriate ads.

Yandex Mobile Ads iOS SDK is a third-party advertising SDK, with AppMetrica initialized automatically per the vendor's integration FAQ. The vendor's App Store privacy disclosures list conditional device advertising ID collection subject to permission. Even without IDFA, we must trace and document network, device and ad-request information passed to the vendor and get an acceptable decision under 5.4. **Do not treat “nonpersonalized” as automatic compliance.**

This review is not a blanket conclusion that all advertising is disallowed; it is a no-shipping rule until documented compliance.

Official references:
- Apple Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Yandex iOS SDK 8: https://ads.yandex.com/helpcenter/en/dev/ios/quick-start
- Yandex App privacy: https://ads.yandex.com/helpcenter/en/dev/ios/app-privacy-apple
- Yandex sticky banner: https://ads.yandex.com/helpcenter/en/dev/ios/adaptive-sticky-banner
- Yandex SDK version and system requirements must be rechecked against the vendor's current quick-start page at the time of implementation; figures quoted in the original 27.10 research are not a permanent compatibility guarantee.

## Minimum acceptable UI

1. Single adaptive banner in the scrollable **Settings** or **Activity** view only (exact placement after real-device layout review), with an unambiguous ad label and reporting options as required.
2. Banner must not displace the primary VPN Connect/Disconnect action, obscure errors, onboarding, exclusions, or security/proxy credentials.
3. Never create ad connections or track from the `PacketTunnel` extension. A failed ad call must not affect VPN or cause an infinite retry loop.
4. Avoid ATT prompts and IDFA/targeting unless clearly required and separately approved; do not pass proxy destination, domains, browsing activity, credentials, VPN health logs, or routing profiles to ad systems.
5. No empty placeholder on ad no-fill/offline; feature flag can completely disable the ad module at runtime and in release config.
6. Human validation of monetization benefits after the first real impression data; >100 downloads alone is not a revenue forecast.

## Exact prerequisites before claiming shipped

- Verify iOS ad unit provenance and availability in partner.yandex.com (current references are insufficient).
- Document Apple 5.4 determination and allowed third-party data treatment; request Apple clarification or independent privacy/legal review where needed.
- Modify privacy disclosures and Store Connect declarations **before publishing** a build that loads ads.
- Test signed build on real iPhone while toggling VPN and switching profiles.
- Separate explicit approval for App Store submission and any production ad activation.

## 28.10 handover and implementation boundary

- Source of this plan: older conflicting docs PR #262. Its `.agent/current-task.yaml` replacement was **not copied**: APL has a live multi-platform operations tracker and rewriting its current-task state would destroy unrelated progress.
- Canonical PR #265 theme work is already merged, and its 0.1.38 release is independently visible in Apple Lookup in 15/16 checked regions. The advertising feature is **not** implemented, enabled, or claimed to be included in that binary.
- Owner's 100+ downloads report establishes commercial interest, **not** an independently verified number or revenue projection.
- This document preserves research only; no SDK, ad unit, App Store listing, Store privacy labels, local network, or VPN tunnel code changed. Any installation/publication requires a separate authorized change.

## Owner-supplied ad unit implementation (2026-10-28)

- `R-M-20288304-1` is the owner-supplied iOS banner placement, not a replacement for Android public App Open `R-M-20130429-1`.
- `App/SettingsBannerView.swift` is a single adaptive sticky banner at the bottom of Settings. It is outside `PacketTunnel`, never blocks VPN controls, has an ad label, and suppresses a failed/no-fill view without retry.
- The ad runtime is **enabled in Release source** (`IOSAdsConfig.isEnabled = true`); the submitted/published binary does not change until a newly signed ad-enabled build is uploaded and reviewed. Debug displays only Yandex `demo-banner-yandex` when Xcode launch arguments explicitly include `-APL_ENABLE_DEMO_BANNER`.
- The owner explicitly requested leaving existing App Store privacy answers unchanged. **No privacy declarations were edited in this branch.** Those answers may no longer describe a build that loads the Yandex SDK; Apple 5.4 and data-disclosure concerns remain unresolved and must not be described as verified compliant.
- The integration's presence in source or an unsigned QA build is not evidence that ads are running in the published App Store app.

## Ad-enabled candidate (explicit owner directive, 2026-10-28)

- Source flag enabled for Release, production banner `R-M-20288304-1`, allocated iOS `0.1.39 (44)` for a distinct build from the already-uploaded build 43.
- Existing App Store privacy fields, privacy policy and `PrivacyInfo.xcprivacy` unchanged at owner's request; no claim of SDK data-flow compliance is made.
- No signed ad-enabled IPA or App Store submission has been verified. GitHub branch/PR is source staging only. Any Apple approval/rejection must be reported as an actual portal result rather than assumed.

## 30.10.2026: published 0.1.39 (44) banner visibility regression

- Apple App Store Connect verified published 0.1.39 uses build 44 with production RSYA enabled; public iTunes Lookup confirmed 0.1.39.
- The banner was only below Version at the very bottom of the Settings ScrollView; no ad was presented on Home. Its own SwiftUI view artificially imposed a height of **1 pt until `onAdLoad`**, and a failure was silently hidden. This placement/constraint was a concrete source-level defect; the exact Yandex ad delivery result on the owner's physical iPhone is **not yet known**.
- Fix candidate 0.1.40 (45): place one banner via `safeAreaInset(edge: .bottom)` on iOS tab shell (not PacketTunnel), remove artificial 1pt height and pre-load opacity suppression, preserve Yandex adaptive min 50 pt, add OSLog `subsystem=ru.arvectum.proxylauncher.ios,category=RSYA` success/failure/impression events. No retry storm.
- Yandex official sticky-banner guide confirms adaptive sizing and warns incorrectly constrained dimensions can break rendering. Real creative/no-fill and actual impression must be tested on a physical device. `tun2proxy.xcframework` in repository does not include an iOS Simulator slice; simulator full-app build therefore fails on the tunnel binary, while generic iPhone builds work.
- Existing App Store Connect privacy declarations and main/tunnel privacy manifests unchanged. This is a next-version candidate, not evidence of an already updated App Store listing.
