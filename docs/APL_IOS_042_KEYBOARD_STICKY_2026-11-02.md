# iOS 0.1.42 — native keyboard gesture and adaptive sticky width

2026-11-02. Source-only UX and advertising layout refinement.

## Behavior
- On iOS 16+, scrolling either the proxy import Form or the create/edit proxy Form dismisses the software keyboard interactively. This uses SwiftUI's native `scrollDismissesKeyboard(.interactively)`, not a custom gesture that could intercept text editing, scrolling or system back navigation. iOS 15 retains the original Form behavior.
- The only production RSYA placement is the existing sticky banner below the TabView. Removed a 16pt horizontal inset from its outer host so `BannerSize.sticky()` receives the entire available safe-area width. The SDK calculates the banner height; no forced `320×50` dimensions or artificial equal-height wrapper are introduced.
- Yandex SDK 8.x handles adaptive sticky auto-refresh. No app-owned refresh timer is added, avoiding duplicate requests and ad-load retry storms. The existing fallback suppresses repeated loading after failure.
- No change to banner unit ID, App Store metadata, privacy declarations, entitlement profiles, VPN engine or saved profiles.

## Acceptance
- SwiftUI iOS 16+ interactive scrolling test added to `ProxyImportUITests`. It types a reserved `.invalid` URL, swipes a visible Form row and verifies the keyboard disappears; it does not save a profile.
- Required before release: simulator execution of this test; a real iPhone check of keyboard gestures in both Forms; actual loaded RSYA height/width and tab bar clearance under compact portrait and large text.
- This task is not a new Apple submission and does not alter the submitted 0.1.41 or installed iPhone.

Docs: https://ads.yandex.com/helpcenter/en/dev/ios/swiftui/adaptive-sticky-banner and https://ads.yandex.com/helpcenter/en/support/faq/sdk-integration
