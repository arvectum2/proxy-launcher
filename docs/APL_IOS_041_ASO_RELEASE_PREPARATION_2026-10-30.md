# APL iOS 0.1.41 — release preparation, no live Apple changes

30 October 2026. **Owner explicitly chose to preserve the submitted Apple review of 0.1.40.** This preparation makes no Apple changes and does not enable Watchdog.

## Current Apple source of truth (authenticated, GET-only)

- 0.1.40 is `WAITING_FOR_REVIEW`, Apple build **45**; currently two App Store listing localizations (`ru` and `en-US`).
- 0.1.39 is `READY_FOR_SALE`. The next version 0.1.41 does **not** exist in App Store Connect yet.
- Apple documentation requires current version status Ready for Distribution for creation of the next App Store version. The exact API gate in our workflow is **0.1.40 `READY_FOR_SALE`**. No review withdrawal or submitted-version edit was attempted.

## Prepared deliverables

1. **Signed iOS 0.1.41 (46) candidate**: full Xcode archive + locally exported 4,216,515-byte IPA, Apple Distribution signature verified, PacketTunnel extension included, all **50 language** bundles present. SHA256 `e81f2b9bb7ec7990ae01a4ab5dc2ebf6564a889cd2162108c465af3f043e0151`.
2. **Durable artifact storage** `/Volumes/ArvectumSSD/Arvectum/releases/APL-iOS-0.1.41-46-homefit-final-20261030/` (candidate-manifest.json, export/archive logs, IPA, archive, isolated build source). Git source files remain unchanged by the version bump.
3. **47 App Store localizations** in `mobile/ios/ASO/metadata/` and `localizations.json`; **94** native-language original iPhone screenshots in `screenshots/`, 1206×2622 JPEG.
4. `mobile/ios/ASO/build_release_041.py`: reproducibly stages *separate* signed iOS 0.1.41 build without altering repository source or App Store Connect.
5. `mobile/ios/ASO/prepare_version_041.py`: read-only future version check; can create exactly 0.1.41 (POST) only after 0.1.40 reaches `READY_FOR_SALE`. Preserves release policy `AFTER_APPROVAL` from last version and refuses duplicates.
6. `mobile/ios/ASO/import_appstore.py`: strictly targets 0.1.41 for writes, requires 0.1.40 `READY_FOR_SALE` and 0.1.41 editable, supports single-localization preflight, idempotent filenames, MD5 and Apple screenshot `COMPLETE` processing verification, read-only check.
7. `mobile/ios/ASO/upload_release_041.py`: read-only offline/Apple check; guarded IPA upload and separate guarded build-46 attachment once Apple processing state `VALID` and linked prerelease version match. No implicit submission.

## Handoff for actual release

Follow the exact command sequence in `mobile/ios/ASO/README.md` when 0.1.40 is finished and Ready for Sale. First preflight Apple GET-only. Next create 0.1.41, perform a single ASO locale dry import + verify, import all and verify 94 processed images, upload and attach signed build 46, verify the final product page and then decide on separate submission to review. Check live Apple build numbers at that time: repackage with a higher number if build 46 has been consumed.

**External prerequisite:** Apple must finish reviewing and publish 0.1.40. There is no background job/automated monitoring created because the Proxy Launcher Watchdog remains disabled as instructed. No Apple App Store Connect write, privacy declaration change, submission cancellation or action on Android/desktop was performed.
