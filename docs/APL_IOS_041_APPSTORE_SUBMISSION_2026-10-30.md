# Arvectum Proxy Launcher iOS 0.1.41 — Apple release execution

Release initiated 30 October 2026, with explicit owner's instruction to complete iOS 0.1.41 to App Review. Source in `arvectum2/proxy-launcher`, branch `feat/apl-core12-locales-20261029` (PR #272). Existing published iOS 0.1.40 and Apple privacy questionnaires remain unchanged; the Watchdog was not enabled.

## Verified signed binary

- Version **0.1.41**, build **46**, bundle ID `ru.arvectum.proxylauncher.ios`.
- Apple Distribution signed IPA, 50 iOS UI localization bundles and PacketTunnel; restored genuine Yandex Mobile Ads production banner integration.
- Mac mini immutable source artifact: `/Volumes/ArvectumSSD/Arvectum/releases/APL-iOS-0.1.41-46-rsya-final-20261030/exported/Arvectum Proxy Launcher.ipa`.
- SHA-256 `fb533576654ebbf2de0f4bfc120d76bebbfaae8f426ecd03b848f78614de3bf1` (12,012,342 bytes).
- Apple's build upload delivery ID `1cfa1339-ce4d-4bbf-8351-758e4a7e01fe`, uploaded successfully, processed `VALID`, attached to iOS 0.1.41.
- Apple build encryption-exemption field set to `false`, as for accepted prior build 45. No privacy questionnaire updates.

## Apple ASO and screenshots

- Apple version ID `bef9d70e-a8e1-432e-b18b-090636321758`, initially `PREPARE_FOR_SUBMISSION`.
- Full **47 official App Store ASO locales**, including required regional variants; all **47 version-localization and 47 app-info records** verified in Apple API.
- **94 actual iPhone Simulator screenshots**, 1206×2622 JPEG, 2 per region, uploaded and Apple processing confirmed `COMPLETE` (not just transport `UPLOAD_COMPLETE`).
- 50 iOS localized UI catalogs, 155 strings each; technical parity and editorial QA completed in preceding PR stages. The eight app languages without native Apple market localization remain localized within the binary.
- App Review notes refreshed to describe version 0.1.41. Previously published review and privacy declarations unchanged.

## Verification and submission

- Full `python -m unittest discover -s tests` on Python 3.12/Tk: **1077 tests passed, 6 skipped**, no failures.
- Importer patched to reuse App Store-created version-localization entries and renew JWT after a `401`, with Apple asset processing `COMPLETE` required before review.
- `mobile/ios/ASO/submit_review_041.py` validates all 47 listings, 94 processed images, `VALID` build 46 and exact build attachment before sending review.
- **Final Apple review-submission state/ID:** `57577081-0511-42b1-b05c-c01e26c27b9c` — `WAITING_FOR_REVIEW`; iOS 0.1.41 state `WAITING_FOR_REVIEW`, submitted at `2026-10-30T20:51:48.942Z`. Verified by authenticated Apple API.
- PR #272 has two unrelated Linux AppImage runtime checksum acceptance failures; iOS source/test/build checks passed. The App Store release does not require those Linux packages.

Apple's approval and eventual App Store distribution remain external, asynchronous platform decisions after successful submission.

## Apple release status

**Submitted to Apple for App Review, not yet approved/published.** Release policy is `AFTER_APPROVAL`, so the actual public App Store release follows Apple acceptance. Do not report 0.1.41 as published until App Store Connect changes to `READY_FOR_SALE`.
