# Arvectum Proxy Launcher — iOS App Store localization package

This directory contains **47 Apple-supported App Store localization records** that map to **42 of the 50 shipped iOS UI languages**, with genuine regional variants for English, French and Spanish. It does **not** represent 47 separate binary languages; the iOS app itself has **50** complete source catalogs.

## Editorial sources and export files

- `localized-copy.psv` — ChatGPT-authored localization and ASO copy, including native-language terminology, descriptions, feature statements and search words. Regional variants have independent keyword choices.
- `build_metadata.py` — deterministic generator and Apple hard-limit validator; **no network or App Store Connect write operations**. Run `python3.14 mobile/ios/ASO/build_metadata.py` from the repository root after changing source copy.
- `localizations.json` — canonical JSON payload for an eventual authorized App Store Connect import. App-level `name` and `subtitle` map to `appInfoLocalizations`; `description`, `keywords`, `promotionalText`, `whatsNew`, `supportUrl` and `marketingUrl` map to `appStoreVersionLocalizations`. The existing App Store privacy declaration is outside this payload.
- `metadata/<apple-locale>/` — per-locale `name.txt`, `subtitle.txt`, `description.txt`, `keywords.txt`, `promotional_text.txt`, `release_notes.txt` and `screenshot_copy.json`. UTF-8 everywhere.
- `screenshots/<apple-locale>/` — two **actual iOS Simulator screenshots** per locale, no fabricated connection states: `01-first-connection.jpg` and `02-local-privacy.jpg`. These show the app's genuine onboarding and explanatory UI. They are not hypothetical mockups. Region variants that share the same iOS UI language reuse the same native screenshots; their metadata remains region-specific.

## Apple constraints and mapping

- Product name at most 30 characters; local subtitle at most 30 characters; promotional text at most 170; description at most 4000; keywords at most **100 bytes in UTF-8** (not 100 Unicode characters).
- Current package supports 47 locales and the official BCP-47/API variants, including `bn-BD`, `gu-IN`, `kn-IN`, `ml-IN`, `mr-IN`, `pa-IN`, `ta-IN`, `te-IN`, `ur-PK`, `ar-SA`, `no` (for app `nb`) and regional English/French/Spanish versions.
- Apple currently doesn't expose separate App Store listing language variants for 8 existing iOS UI languages: Persian `fa`, Uzbek `uz`, Filipino `fil`, Swahili `sw`, Hausa `ha`, Amharic `am`, Bulgarian `bg` and Serbian `sr`. These languages **remain localized inside the iOS binary** and receive Apple's supported listing fallback. There is no invented non-Apple ASO locale.
- Screenshot originals are 1206 × 2622 (Apple-supported Dynamic Island medium iPhone portrait size) and stored as opaque JPEGs. No App Store Connect upload performed.
- All claims focus on verified functions in the iOS source: self-configured HTTP / HTTPS CONNECT / SOCKS5 connections, profiles, fallback/priority, direct website exclusions, optional iOS Shortcuts user-created automations and locally held credentials. App name is consistent for all markets.

## Release workflow

1. Run the metadata generator and `python3.14 -m pytest -q tests/test_ios_aso_editorial.py tests/test_ios_aso_screenshots.py`.
2. Inspect screenshot text overflow, RTL and native Shortcuts terms at all large accessibility sizes, then obtain an independent human-language review if required by the release process. The current translations are authored and edited by ChatGPT; no third-party human linguist has been represented as consulted.
3. For a **new, editable** iOS version in App Store Connect, import localizations and screenshots only after release authorization. Keep the live card and privacy information untouched until specifically instructed.
4. If editing screenshots, preserve actual application content. All visible UI must reflect real features; do not invent successful proxy connections or add product claims unsupported by the app.

**Sources**: Apple App Store localization and screenshot specifications, and App Store Connect metadata property limits (2026-10-30). See `docs/APL_IOS_50_EDITORIAL_ASO_QA_2026-10-30.md` for local test evidence.

## Repeatable App Store Connect import (review-safe)

`import_appstore.py` uses only Python standard library, Xcode's `altool` and the existing local App Store Connect credentials. It was tested against Apple with **GET requests only** on 30 October 2026. Its execute path has an explicit confirmation gate and checks the app version state *before any write* and again before each locale.

```bash
# Fully offline validation: 47 ASO locales, 94 screenshots, zero writes
python3 mobile/ios/ASO/import_appstore.py

# Read current version and localization count directly from Apple; no writes
python3 mobile/ios/ASO/import_appstore.py --live-check --version 0.1.40

# ONLY when a new/current version has an Apple-editable status and is authorized
python3 mobile/ios/ASO/import_appstore.py --execute --version 0.1.41 --confirm-version 0.1.41
```

The tool supports idempotent locale creation/update and screenshot asset reservations, byte-range image uploads, MD5 commits and local verification of matching locales. It never changes App Store review submissions, build attachment, app privacy metadata, or published versions. Each locale's `appInfoLocalization` and `appStoreVersionLocalization` are created together to avoid mismatched version and app locale sets. Existing screenshot file names are reused rather than overwritten. It fails closed for noneditable Apple states. On a new version, verify Apple's exact screenshot-set display type `APP_IPHONE_61` compatibility with the accepted 1206 × 2622 medium iPhone asset on the first locale before the full import; the asset API only validates it during actual uploading.

**Current real App Store state (30 October 2026):** iOS `0.1.40` = `WAITING_FOR_REVIEW`, with only `ru` and `en-US` card localizations; it is not currently editable for screenshots. Apple explicitly forbids new screenshot uploads while Waiting for Review. To deploy the prepared ASO package, either the owner must explicitly choose to withdraw and resubmit that version or we can import into a later editable iOS version after Apple's current review completes. No cancellation or App Store Connect write was performed.

## Next release 0.1.41: prepared without changing 0.1.40 (30 Oct 2026)

**Owner choice is to preserve the current Apple review of 0.1.40.** It is `WAITING_FOR_REVIEW` with submitted build **45**. Apple's version-creation workflow requires the current version to become *Ready for Distribution* (App Store Connect API `READY_FOR_SALE`) before a new version can be created.

### Durable signed candidate on Mac mini

A complete 0.1.41 (**build 46**) signed Apple Distribution archive and IPA, prepared from PR #272 iOS source in a separate staging directory, are stored at:

`/Volumes/ArvectumSSD/Arvectum/releases/APL-iOS-0.1.41-46-20261030/`

- IPA: `exported/Arvectum Proxy Launcher.ipa`
- Archive: `APL-0.1.41-46.xcarchive`
- Integrity manifest: `candidate-manifest.json`
- SHA-256: `eae05d373e6b3547618df4340fe3cfc7fbde1f70fde560b1095b34cef13a3916`
- 50 iOS localizations + PacketTunnel, valid deep code signature. The candidate was **not uploaded to Apple** and is not in Git.
- Rebuild reproducibly from a new isolated directory with `python3 mobile/ios/ASO/build_release_041.py --output /path/to/new/output`. The script **does not modify the source checkout**. Build number 46 was valid when prepared; verify no later upload has consumed that number before submitting.

### When 0.1.40 finishes review and is Ready for Sale

Run in the checked-out repository on Mac mini. The first commands are **read-only**:

```bash
python3 mobile/ios/ASO/prepare_version_041.py --live-check
python3 mobile/ios/ASO/upload_release_041.py --live-check
python3 mobile/ios/ASO/import_appstore.py --live-check --version 0.1.40
```

When those show 0.1.40 `READY_FOR_SALE`, a new, explicitly authorized iOS release workflow can proceed. **Do not create 0.1.41 earlier or withdraw 0.1.40**.

```bash
# CREATE 0.1.41 (Apple POST only once; repeat is idempotent)
python3 mobile/ios/ASO/prepare_version_041.py --create --confirm-version 0.1.41

# STAGE ASO: upload one new market first, verify Apple's processed assets
python3 mobile/ios/ASO/import_appstore.py --execute --version 0.1.41 --confirm-version 0.1.41 --only-locale en-GB
python3 mobile/ios/ASO/import_appstore.py --verify-only --version 0.1.41 --only-locale en-GB

# Remaining ASO; repeated runs reuse existing locale/image filenames
python3 mobile/ios/ASO/import_appstore.py --execute --version 0.1.41 --confirm-version 0.1.41
python3 mobile/ios/ASO/import_appstore.py --verify-only --version 0.1.41

# UPLOAD signed build to Apple processing, then attach after VALID status
python3 mobile/ios/ASO/upload_release_041.py --upload --confirm-version 0.1.41
python3 mobile/ios/ASO/upload_release_041.py --attach --confirm-version 0.1.41
```

The verify command fails closed if Apple is still processing a screenshot (`UPLOAD_COMPLETE`), has failed processing it (`FAILED`) or returns a different MD5. Retry the read-only verify later; **do not blindly duplicate** a processing image. The binary upload uses Xcode's authenticated altool and needs Apple to finish processing before the attach command. No script automatically submits a review or releases the app; submit 0.1.41 only after validating all 47 locale records, 94 screenshots, a VALID build 46 and owner release instructions. The new-version creation, upload, and attachment code paths have unit-test coverage but have **not** been executed against the Apple write API, so the first live locale must be explicitly verified.

Source references: [Apple — Create a new version](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version), [Create an App Store version API](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-appstoreversions), [Upload and verify assets](https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect), [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds).
