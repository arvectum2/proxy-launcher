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
