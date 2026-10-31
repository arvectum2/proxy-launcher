# APL iOS — App Store Connect ASO import handoff (30 Oct 2026)

## Objective and latest verified state

User requested final completion of 50 iOS source locales and 47 App Store ASO localizations. Assets and signed IPA were already complete in PR #272. Newly verified via authenticated read-only App Store Connect API:

- `0.1.40`: **`WAITING_FOR_REVIEW`**, currently `ru` and `en-US` version and app-info localizations; Apple's App Review submission is already active.
- `0.1.39`: **`READY_FOR_SALE`**. No change made to the published version.
- Apple App Store Connect rules expressly prohibit editing/uploading screenshots while the app version is Waiting for Review. Cancelling review would reset the submission/review clock; the user has not specifically chosen that action.

## Completed, tested, and pushed

- 50/50 iOS interface source catalogs plus 47 official Apple metadata variants and 94 authentic iOS screenshots remain committed. Correct native iPhone screenshot size 1206 × 2622 was confirmed with Apple's specifications.
- Fixed CI regression: Pillow (`PIL`) was imported in a test but not installed by CI. Replaced dependency with Python standard-library JPEG header/parser and image-dimension check.
- Fixed pre-existing Windows CI Unicode decode failure in `tests/test_core12_editorial_review.py` by specifying `encoding='utf-8'` for all file reads.
- New read/write-gated, idempotent App Store importer at `mobile/ios/ASO/import_appstore.py`, instructions in `mobile/ios/ASO/README.md`. Does not use browser UI, only ASC REST and Xcode altool credentials, and does not expose secrets.
- `--live-check --version 0.1.40` was successful: two existing locales and `WAITING_FOR_REVIEW`, **zero writes**. Even with matching `--execute --confirm-version 0.1.40`, importer stopped with exit 2 before write. Five unit tests for the offline plan, explicit confirmation, Apple status safety and screenshot reservation logic passed.
- CI after test repairs: Doctor checks and most checks now pass; remaining acceptance/Linux/macOS packaging checks are outside this iOS-only scope. The PR is not merged into main.

## Only remaining external decision

1. Preserve current review of 0.1.40 and import prepared 47 ASO locales + 94 screenshots to the next editable version after Apple finishes its review (recommended to avoid restarting the current review); **or**
2. Explicitly authorize withdrawing 0.1.40 from App Review, importing metadata/screenshots into the now-editable version, then resubmitting it. This resets the review process and requires a separate deliberate business decision.

No App Store Connect changes or review cancellation have occurred in this task. The importer may need a first-locale live upload check for Apple's screenshot-set type before the 94-image campaign; the dry run and read-only API are verified, not the write path against the live API.

Official references: https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-submission-statuses/ and https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/ and https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect
