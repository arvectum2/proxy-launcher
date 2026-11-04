# APL iOS 0.2.0 — RSYA banner RCA and actual-device Release QA

Date: 2026-11-03. Branch: feat/ios-020-smart3-exact-flow-direct-20261103.
No App Store Connect submission, merge or public release was made.

## Cause of missing ads on the owner's iPhone

The preceding Smart3 physical XCTest sessions installed a Debug-signed iOS app.
SettingsBannerView.swift explicitly disables SDK advertising in Debug unless
the launch argument -APL_ENABLE_DEMO_BANNER is supplied. In that mode the
banner/native SDK uses Yandex demonstration placements.

The production Release configuration was always enabled, using real registered
RSYA banner R-M-20288304-1 and native R-M-20288304-2. Historical preference
values labeled impression are not enough to prove ads actually loaded in the
last Debug session. We therefore backed up and temporarily removed three
diagnostic ad markers before each real SDK test.

## Real hardware results

iPhone 13 iOS 27.2, APL version 0.2.0 build 48:

1. Explicit Debug demo QA: after clearing all three RSYA diagnostic markers,
   launching with -APL_ENABLE_DEMO_BANNER produced new primary, secondary
   and native impression callbacks. Debug native now uses official
   demo-native-content-yandex, never a production unit.
2. Actual optimized Swift Release configuration, using the original
   existing Apple Development signing identities for a reversible local
   iPhone installation. No test launch flags and no demo ad IDs.
   After clearing markers and launching normally, the primary real banner
   and real native unit both produced NEW impression callbacks within
   about 18 seconds. No secondary banner was expected because native filled.
3. All 11 App Group and 20 application preference values were restored from
   the private pretest backup. Per-value SHA-256 equality confirmed 31/31.
   The owner now has Release-compiled, Development-signed iOS 0.2.0 (48)
   installed on the iPhone, launched without QA/demo flags. Original proxy
   and VPN profile data were not changed.
4. The opt-in hardware ad XCTest built successfully but the UI runner timed
   out while enabling automation mode on this device. Do NOT count this
   test as passed. The standalone SDK request/impression results were
   verified independently from fresh local preference evidence on the
   physical device, not by mocking the render lifecycle.

## Hardened behavior and compulsory release guard

- Debug native ad tests use an official Yandex demo native ad unit.
- Release still uses primary R-M-20288304-1 and native R-M-20288304-2.
- No-fill/network failures do not loop requests. Primary can retry a bounded
  number of times and, after a 15 min cooldown in a later foreground session,
  can recover. Native allows a second attempt only after a 30 min cooldown
  and foreground return. The independent backup banner placement is retained.
- Errors record only SDK code/domain; verbose SDK logging is Debug opt-in.
- scripts/ios_active_release_preflight.py rejects missing or disabled
  production ad IDs, missing Home native/primary placements, SDK initialization,
  absent XcodeGen SDK dependency, or absent SKAdNetworkItems. --ipa additionally
  checks the exported IPA itself for the actual SDK binary, app signature,
  Packet Tunnel, signed app version and SKAdNetwork.
- The advertising server may legitimately return no-fill or fail under
  network restrictions. No client implementation can guarantee an actual
  creative impression at every launch.

## Latest signed distribution candidate

- Archive: /private/tmp/APL-iOS-020-Smart3-FinalAdsLive-20261103.xcarchive
- Local IPA: /private/tmp/APL-iOS-020-Smart3-FinalAdsLive-20261103-export/Arvectum Proxy Launcher.ipa
- IPA size 9,060,018 bytes, SHA-256:
  5ef331c13fcd81995e313e77a97245807edd65ac1ef00e6aee324809f1940ff7
- Apple Distribution archive and App Store-format local export PASS.
- IPA ZIP integrity and app + Packet Tunnel deep codesign PASS.
- iOS 0.2.0 (48), YandexMobileAds framework binary, Packet Tunnel and
  228 SKAdNetworkItems all independently verified inside the exported IPA.
- App's existing ad unit IDs and privacy metadata remained unchanged.
- Older local iOS 0.2.0 IPAs are superseded. Do NOT upload older builds.
- No App Store Connect upload happened.
