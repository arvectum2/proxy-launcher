# APL iOS 0.1.41 — Apple release readiness audit, 30 October 2026

## Apple read-only verification

- App Store Connect authenticated API: 0.1.40 `READY_FOR_SALE`; 0.1.41 is not created or uploaded. Last uploaded and processed build is 45; next candidate 46.
- Do not modify the live 0.1.40, published privacy declarations, or disabled watchdog. Creating/importing/uploading/submitting 0.1.41 are separate Apple API write operations.

## What is technically verified

- 50 iOS catalog languages, 155 keys each. `audit_ios_copy.py`: **0 errors** for catalog key parity, placeholder mismatches, suspicious untranslated large English text and whitespace/Unicode. This is technical consistency, **not** independently certified native-speaker fluency.
- All 47 Apple ASO localization entries and 94 real simulator screenshots are present; local metadata fields and 100-byte keyword limit pass tests. Eight iOS source languages rely on App Store-supported listing fallback (`fa`, `fil`, `sr`, `bg`, `ha`, `am`, `sw`, `uz`) and remain localized in the binary.
- Simulator geometry matrix: 380/380 previously verified across 50 languages including banner *footprint* of 90–100 pt and RTL and large accessibility labels. The real ad SDK view is **not in this iOS source**, so **actual ad placement/loading has not been integration-tested**. The Debug-only banner rectangle disappears in the signed Release build.
- Repaired two macOS Catalyst Home contract regressions in `tests/test_macos_appstore_contract.py`; preserved actual equal-height Catalyst dashboard by conditional `dashboardCardMaxHeight` while the iPhone remains intrinsic-height.
- Full `python -m unittest discover -s tests` through Python 3.12/Tk: **1073 tests pass, 6 skipped**; no failures. Full iOS simulator application build succeeded.
- Previous PR #272 CI failures (nine jobs) were traced to the same two obsolete Catalyst tests in Doctor, Windows clean/installer and macOS packaging unit stages. This fix was validated locally, but remote GitHub CI still needs to report green after a new push.

## Latest signed release candidate

Local archive + IPA on Mac mini SSD: `/Volumes/ArvectumSSD/Arvectum/releases/APL-iOS-0.1.41-46-rc-audit-20261030/`.

- iOS 0.1.41, build 46; 50 language bundles, 1 PacketTunnel.
- Apple Distribution archive and signed exported IPA, `codesign --verify --deep --strict` succeeded.
- IPA SHA-256: `a0b3e773f7f4be024c4b9e627251cb08799b5d923d9b52bf745dff65c6f27df2`; 4,216,469 bytes.
- No App Store Connect version or upload created, and no current review was modified.

## Outstanding release gates

1. Actual banner SDK integration and UI validation of live adaptive creative (if that functionality is required for 0.1.41). The QA placeholder is *not* a real advertising banner.
2. Green remote PR CI/merge before treating branch as fully accepted. All known nine old failures appear to derive from tests corrected here, but their new results must be awaited.
3. ASO importer write path has offline mocked tests and live GET/status guard only, so import the first locale and verify Apple accepted its image before bulk import. Review release copy/metadata with final owner approval.
4. After the user explicitly requests publication, create/edit 0.1.41, import 47 ASO entries and 94 screenshots, verify them on Apple, upload signed build 46, attach it, and submit for review. Neither these external writes nor independent linguistic signoff has been performed as of this report.
