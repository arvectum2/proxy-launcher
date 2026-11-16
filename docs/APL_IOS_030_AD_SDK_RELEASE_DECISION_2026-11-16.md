# iOS 0.3.0 — ad SDK release decision, 16 November 2026

**Historical review only — superseded by the owner decision of 16 November 2026. No active decision, follow-up, reminder or monetization change. See AGENTS.md.**

Historical status before owner reaffirmation: unresolved product/privacy decision. No change to advertising,
installed app, Apple metadata, public policy, SDK or distribution.

## Verified facts

- Lock: Yandex Mobile Ads 8.6.0, AppMetrica 6.7.1. The exact historical
  bundle audit manifest b41447f9163ca958e931b5850f454aff1bdc7bc771011a2b14dc37661beecd83
  was rehashed. 26 declarations, 7 declaring collection, 1 declaring tracking.
  The previously audited isolated lab has identical declaration paths/hashes.
- Ads SDK: DeviceID and AdvertisingData. AppMetrica AdSupport: DeviceID
  linked/tracking, analytics; tracking.appmetrica.yandex.net and
  tracking.reserve.appmetrica.yandex.net. Other components declare coarse
  location, interaction, purchases, crash, performance and other data.
  These are declarations, not observed transfers.
- App-owned startup gates explicit initialization on disclosure acceptance.
  No app-owned setUserConsent, setLocationConsent, ATT request or
  AppMetrica data-sending configuration calls found in app/shared/provider
  code. Acknowledgment is not equivalent to granular collection consent.
  The vendor says it initializes AppMetrica automatically with ads.
- The repository policy docs/privacy.html claims no advertising/analytics
  SDK in current iOS releases. This contradicts the exact inspected bundle;
  do not certify or publish it unchanged for iOS. Hosted policy and current
  App Store labels have not been independently verified in this review.
- Both SDK attribution phrases exist in the About view and all 50
  repository ASO description records. Actual live listing and distribution
  terms for each final artifact still need verification.

## Official documents checked on 16 November 2026

1. https://developer.apple.com/app-store/review/guidelines/ — 5.4 VPN
   imposes organization, prior disclosure and special restrictions on data
   use/disclosure to third parties; 5.1 also requires transparent consent
   and withdrawal. Do not assume ordinary advertising consent overrides 5.4.
2. https://developer.apple.com/app-store/app-privacy-details/ — include
   third-party code practices in accurate privacy labels.
3. https://ads.yandex.com/helpcenter/ru/dev/ios/app-privacy-apple — describes
   ID collection under permission and developer responsibility for disclosures.
4. https://ads.yandex.com/helpcenter/en/support/faq/sdk-integration —
   AppMetrica required for correct advertising SDK operation and initialized
   automatically at SDK initialization and banner requests.
5. https://appmetrica.yandex.com/docs/ru/sdk/ios/analytics/ios-operations —
   standalone AppMetrica has data sending controls; no evidence those controls
   fully cover the embedded advertising integration or meet Apple 5.4.
6. https://yandex.com/legal/mobileads_sdk_agreement/en — clause 3.3
   requires attribution in About, download description and package description
   file if created. Current source attribution observed; no legal clearance.

## Proposed decision

A. Retain RSYA only after written vendor clarification covering the locked
   versions plus Apple clarification for VPN applications where needed.
   Validate the exact candidate and effective consent, disclosures and
   runtime transfer behavior. The no-collection claim is not accepted.
B. Recommended for the conservative next iOS release: after owner approval,
   explicitly remove the advertising SDK and its analytics transitive
   dependencies from the iOS target, not just hide the banner. Remove
   advertising initialization paths and unused configuration, recheck
   project and lock, archive symbols/dependencies/manifests, first-run UX,
   localizations, metadata and policy, and ordinary release tests. No
   change to other platforms. Monetization can separately use an approved
   App Store purchase model. This proposal is not authorization to change
   monetization and does not itself clear remaining VPN privacy gates.

Questions for Yandex: for SDK 8.6.0 with AppMetrica 6.7.1, identify every
device/user datum transmitted or retained on startup and banner requests,
including no ATT permission and refused consent; provide supported complete
opt-out configuration before SDK startup, evidence that automatic
AppMetrica collection is disabled in that configuration, effect on ad
delivery, retention/recipients/transfers, and any documented Apple 5.4
compatible VPN integration. Do not transmit owner information or logs
with this inquiry. Inquiry is drafted, not sent.

Neither consent alone, SDK tracking declaration alone, nor a previous
App Store approval is sufficient to establish the next release complies.
No final labels, effective policy, legal conclusion or publication approval
is asserted here. Native production integration is independently incomplete.
