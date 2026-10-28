# APL iOS 0.1.38 build 42 — theme and Arvectum.com metadata

Status: **Submitted to Apple App Review — WAITING_FOR_REVIEW** on 2026-10-27. Public release is pending Apple approval.

## Changelog
- Settings → Appearance provides System / Light / Dark theme modes, persisted via local AppStorage.
- System is the default and follows dynamic iOS appearance changes; light appearance has a dedicated semantic palette for text/background/buttons; dark palette remains the established Arvectum brand appearance.
- App Store Support URL and Marketing (Developer Website) URL set to `https://arvectum.com/` in `ru` and `en-US`. These are App Store version **metadata** changes, not VPN/PacketTunnel changes.
- No advertising SDK, analytics or user-traffic changes introduced.

## Live Apple API evidence
- Existing live `0.1.37` (build 41): READY_FOR_SALE, currently points to GitHub, remains unchanged.
- New version `0.1.38`: App Store Connect id `2f7d4c38-ff0c-4ca5-81c5-6bfeeab768f6`, `PREPARE_FOR_SUBMISSION`, manual release type.
- `ru` localization id `60315bd2-dcda-48e1-84d3-2306bfa3cde7`: both `marketingUrl` and `supportUrl` PATCH HTTP 200; subsequent GET confirmed `https://arvectum.com/`.
- `en-US` localization id `72f4574f-e633-430d-b13f-0d2df98d9c5f`: same PATCH and GET verified.
- `https://arvectum.com/app-ads.txt` publicly accessible; Yandex RСЯ verification is only expected after the **public** App Store Developer Website URL points to arvectum.com.

## Release acceptance
- Swift package tests: PASS on Xcode 27.1 Mac mini.
- Unsigned iPhone Release build: PASS. Pre-existing Swift 6 concurrency warnings in ProxyProbe and TLSProxyRelay do not fail Swift 5.9 build.
- Apple Distribution signed archive: PASS; codesign deep/strict PASS; exact app ID `ru.arvectum.proxylauncher.ios`; build 42.
- App Store IPA export: PASS; IPA SHA-256 `0f80cf1bb42596bf497baa38a713c9dc11c48cdeaf6de4705699767ae8135a84`.
- Apple `altool --validate-app` and `--upload-app`: successful, final exit 0; a transient HTTP 500 during validation was recovered by the upload service automatically.
- App Store Connect `buildUploads` 0.1.38(42): `COMPLETE`, zero warnings/errors.
- App Store Connect `builds`: build ID `73fbe779-2f35-4f7e-abb2-bedfb24cbba7`, `VALID`, `usesNonExemptEncryption=false`, attached to version `2f7d4c38-ff0c-4ca5-81c5-6bfeeab768f6` (relationship GET verified).
- `ru` and `en-US` `supportUrl` + `marketingUrl`: `https://arvectum.com/`, What's New verified in both localizations.
- Review submission ID `ecae724b-0cc2-4e51-bc5d-92c15d107277`, request PATCH `submitted=true` HTTP 200, state `WAITING_FOR_REVIEW` verified on current iOS app version.
- Configured `releaseType=AFTER_APPROVAL`: Apple may publish automatically after accepting review.
- Windows PR #265 CI initially failed due to new UTF-8 test reading and a prior fixed-token UI test. Both regressions were corrected; locked `setuptools` updated to `84.1.0` following pip-audit GHSA. Focused UI contract tests pass 11/11 on Mac mini. Fresh CI and merge remain pending.
- **Not yet complete**: GitHub PR #265 merge, physical iPhone light/dark acceptance, Apple review approval, public App Store 0.1.38 visibility and Yandex RСЯ verification.

No advertising is included: Apple VPN guideline 5.4/privacy review still applies to future ads.
