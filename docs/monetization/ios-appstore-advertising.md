# APL-IOS-ADS-001 — advertising and App Store compliance plan

Status: **RESEARCH APPROVED; SDK INTEGRATION BLOCKED — Apple guideline 5.4 privacy/data-flow assessment.**
Updated: 2026-10-27
Owner signal: >100 App Store downloads (owner report, not verified directly).
Tracking: https://github.com/arvectum2/proxy-launcher/issues/261

## Stable app baseline

- App Store public baseline documented in repository: iOS 0.1.36 / build 40 (published 2026-10-05).
- iOS bundle: `ru.arvectum.proxylauncher.ios`, iOS 15+, native SwiftUI, `NEPacketTunnelProvider` in a separate extension.
- No ad SDK or analytics in this binary. The app's initial disclosure currently promises “Без аналитики и рекламы”, and the public App Store description also promises no ads.
- `Config/AppPrivacy/PrivacyInfo.xcprivacy` sets `NSPrivacyTracking=false` and no collected data, and App Store privacy metadata has “Data Not Collected”. None of these statements may be carried forward unchanged if the ad integration changes real data behavior.
- The repository already has Android-specific Yandex App Open `R-M-20130429-1`. The project has a historical macOS advertising research note. **Do not assume any existing ad unit is registered for the iOS app.**

## Product rollout by gates

| Stage | Deliverable | Status |
| --- | --- | --- |
| P0 — Apple/legal | Document classification under App Review 5.4, SDK full data-flow/privacy analysis, and acceptable advertising method, obtaining written Apple clarification when necessary | **BLOCKED / REQUIRED BEFORE SDK** |
| P0 — RСЯ account | Confirm separate iOS app record and banner ad-unit ID tied to exact App Store bundle; determine supported regions/creatives | NOT VERIFIED |
| P1 — UX | Choose an unobtrusive adaptive banner in Settings or Activity; no banners over connection controls; no interstitial/App Open in MVP | PRODUCT DIRECTION |
| P1 — Build (conditional) | Integrate Yandex Mobile Ads SDK via Swift Package Manager into iOS **main app only**, feature flag OFF and demo unit in debug until compliance | NOT STARTED |
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
- Yandex SDK requirements: Xcode >=16.4, iOS >=15, SDK 8.6.0 listed on current official quick-start page.

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
