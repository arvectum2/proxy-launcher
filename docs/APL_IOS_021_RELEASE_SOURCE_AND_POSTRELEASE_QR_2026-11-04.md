# iOS: source-to-release provenance and two-iPhone QR acceptance after release

Decision recorded on 4 November 2026: the owner will install a NEW APP STORE RELEASE that actually contains QR profile sharing on a second iPhone, test sending and receiving between two devices after that release, and request a subsequent patch release if any defects are found. This explicitly changes only the QR two-device user acceptance schedule; it does not waive unit/CI, signing, privacy, basic device launch or unrelated native VPN/egress risk gates.

## What is actually in 0.2.0(48)?

Apple's submitted signed iOS 0.2.0 build 48 is documented as built from Git SHA f0a93f8addb4b61961e9c53c885871a563aef9c6 (2026-11-04 01:28 MSK). Its source predates the new QR feature. The final reviewed source of QR sender/receiver plus RFC3986 handling was b59801f69990d621e873360762256a80919168de (PR #320), merged only later. Git ancestry and required-file checks prove that iOS 0.2.0(48) does NOT contain this new QR feature. Downloading or testing 0.2.0(48) on the second phone will not exercise it.

The current main after PR #325 DOES include the QR sharing source and diagnostics, but has not yet been signed as a new Apple-distributed release. Version labels and next build numbers are not assigned or published by this change. The feature must be present in the exact future source ref used to build the next Apple-signed archive.

## Reproducible read-only check

The local tool mobile/ios/Tools/verify_release_feature_source.py checks feature introduction commit ancestry and required source files, then emits deterministic JSON.

    python3 mobile/ios/Tools/verify_release_feature_source.py --source-ref f0a93f8addb4b61961e9c53c885871a563aef9c6 --feature qr-profile-share --require-absent
    python3 mobile/ios/Tools/verify_release_feature_source.py --source-ref HEAD --feature qr-profile-share --require-present

Features supported: qr-profile-share and safe-connection-diagnostics. Unknown source refs fail with exit code 2. An unmet --require-present or --require-absent gate fails with exit code 3. No Apple API call, IPA upload, login or network call is performed. Crucially, JSON fields signed_binary_feature_verified and app_store_publication_verified remain false. Ancestor source inclusion is necessary but NOT sufficient for proving that a signed IPA includes/runs the feature; verify archive composition, target compilation, entitlements and actual user experience separately.

## Safe release order

1. Await Apple disposition of the already submitted 0.2.0(48); do not silently replace that binary, edit reviewer metadata or confuse it with a QR-capable build.
2. For the future QR-containing release, freeze and record the precise Git source ref. Run the source ancestry gate, Swift/Python regressions, signed/unsigned device build checks, localized consent/privacy checks and standard App Store submission gates. Do not accidentally package experimental draft PR #314's unverified 2s/30s native FIN/CLOSE_WAIT engine change.
3. Do not claim the actual two-device camera/AirDrop/Messages/VoiceOver feature is already accepted before user acceptance. The OWNER chose to perform this specific two-phone check after distribution, with a clear acknowledgment that a QR regression could require a follow-up App Store update.
4. After that specific QR-capable release reaches App Store, install it on a second iPhone. Test first with a disposable synthetic SOCKS5 profile, then (only if necessary) a real profile, with consent and protected credential handling. Test outbound QR + Apple Share Sheet, native camera and application camera scan, AirDrop/Messages, import confirmation/duplicate handling, IPv6/Unicode/special characters and normal activity of the already-connected VPN. Never place credentials in screenshots or bug logs.
5. Record issues as reproducible regression cases with no secrets and fix them in the following version, with fresh CI and Apple review. Do not assert post-release tests passed until they actually occur.

The physical iPhone 13 already passed isolated synthetic QR generation/pixel decoding/import and real UIKit UIActivityViewController.viewDidAppear; this is partial evidence only. Native in-app camera permission, true transfer between two iPhones, and Apple-distributed 0.1.41-to-0.2.0 Keychain migration remain unverified. The user chose to defer the two-phone QR test, not to waive safety gates for native tunnel/socket changes or Keychain upgrade.


## CI portability of the source gate

GitHub's Windows clean-build and installer workflows use shallow source checkouts: old Apple build and QR source commit objects are absent there. Do not equate unavailable history with a negative feature verdict. Historical real-project assertions run on full local clones and explicitly skip on shallow runners.

Portable tests build a disposable local Git repository with a pre-feature commit, a new-feature commit and a follow-up deletion of a required source file. Seven real-Git tests exercise ancestry, file presence, fail-closed absence, invalid refs and CLI exit codes on all CI platforms without fetching history or contacting GitHub. The production source verifier always rejects unresolved commits rather than returning a spurious positive or a false negative.

Verified on a full local repository: 7 historical-source checks, 7 synthetic Git checks, iOS Python 133 total (1 skipped), Swift Core 159/159 PASS.
