# Advertising plan — native macOS Proxy Launcher

Status: planned after v0.2.18 functional recovery, not integrated into signed build.

## Compliance gate
- Apple App Review section 5.4: VPN apps must not sell, use or disclose users' traffic/data to third parties. Follow its privacy disclosure and organisation rules.
  https://developer.apple.com/app-store/review/guidelines/
- App Review 2.5.18: ads can appear in the main app only, never Packet Tunnel extension; age/report/consent obligations still apply.
- Third-party ad SDKs frequently send device/app telemetry to partners. Do NOT integrate Yandex/AdMob into this VPN app without verifying rule 5.4 compliance, Apple privacy details, and supported Mac Catalyst runtime.
- Yandex Mobile Ads documents iOS and Android but not a specific Mac Catalyst support guarantee:
  https://ads.yandex.com/helpcenter/en/dev/platforms

## Candidate low-risk implementation
- Non-personalised, locally bundled sponsor slot on Help or Settings only, outside Connect / active status, no targeting, network traffic analysis, analytics, SDK, or event reporting.
- Do not display empty placeholders and never modify the VPN extension.
- Update app disclosures and App Store privacy metadata before introducing any sponsorship.

## Release gate
P0: split DNS routing and exclusion correctness. P1: physical QA + UX layout polish. P2: platform-compliant sponsored inventory and business integration.

## 2026-10-14 first-party sponsor slot (development branch, not published)

On the macOS App Store lane, a **manual, locally bundled sponsorship** option is implemented in
mobile/macos-appstore/App/SponsoredPlacementView.swift. It is confined to the main app's
Settings screen and displays only when SponsoredPlacement.json has enabled: true and a vetted,
HTTPS-only target. It is **disabled by default** until a real paid sponsor, approved creative
and privacy review exist. Disabled means no placeholder/ad is visible and no paid impressions
or ad revenue can occur.

Safeguards:
- No Yandex Mobile Ads/AdMob/AppMetrica, network SDK, browser-based ad tag, identifiers,
  page analytics, tracking pixel, or VPN packet/domain use for ad selection.
- Creative copy is bundled with the signed binary and changes require a new build.
- No remote image fetch, auto-redirect or impression beacon; no data leaves the app to
  render the ad. Sponsor site opens **only** when the user explicitly clicks.
- Explicit "Реклама" label, feedback/report email and advertiser attribution.
- URL validation requires HTTPS, disallows query/fragment/user credentials to prevent
  unreviewed click tags. Enabling a placement requires verifying target safety and
  all current privacy/age-rating/store disclosures.

**Not a Yandex mobile SDK integration.** As of this review, Yandex documentation covers
iOS/Android and popular mobile frameworks but provides no dedicated macOS Catalyst
support contract. Their FAQ says AppMetrica is required for the ad SDK to operate.
Given Apple's 5.4 VPN limitation on data use/disclosure, a third-party ad SDK should
not be added to this product without affirmative compliance review.
There is also no sponsor contract or creative in this branch, so the feature is
technical inventory support rather than active paid advertising.

Sources:
- https://developer.apple.com/app-store/review/guidelines/ (2.5.18, 5.4)
- https://ads.yandex.com/helpcenter/ru/dev/platforms
- https://ads.yandex.com/helpcenter/ru/support/faq/sdk-integration
