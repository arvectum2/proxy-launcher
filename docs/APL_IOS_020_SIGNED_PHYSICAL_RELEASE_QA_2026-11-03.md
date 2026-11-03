# iOS 0.2.0 (48) — Signed candidate and physical iPhone QA

Date: 2026-11-03. Source: Draft PR #303 (f9954483), on Smart Exclusions PR #302 and product PR #296. This is a signed, locally exported **release candidate**, NOT an App Store submission. Full automatic Smart3 Safari exact-host DIRECT is still platform-blocked.

## Built and cryptographically verified

- Source preflight: version 0.2.0 / build 48 matches the manifest, XcodeGen spec and Xcode project.
- Xcode 27.1: signed Apple Distribution archive ARCHIVE SUCCEEDED, App Store Connect format IPA EXPORT SUCCEEDED; destination export, **no Apple upload**.
- App and embedded Packet Tunnel version: 0.2.0 (48). Signed bundle IDs: ru.arvectum.proxylauncher.ios and ru.arvectum.proxylauncher.ios.PacketTunnel. Team VML75VY94V.
- IPA ZIP integrity PASS, app deep codesign PASS, PacketTunnel deep codesign PASS.
- Bundle: **64 locales**, Packet Tunnel, and **YandexMobileAds framework**. Privacy/ad source settings unchanged by QA commits.
- Signed IPA (local Mac mini): /Volumes/ArvectumSSD/Arvectum/releases/ios/0.2.0-48/rc-pr303-20261103/exported/Arvectum Proxy Launcher.ipa
- Release archive: /Volumes/ArvectumSSD/Arvectum/releases/ios/0.2.0-48/rc-pr303-20261103/APL-0.2.0-48.xcarchive
- IPA size: 9,032,208 bytes. SHA256: 181f2a74a5a2c05418e3dac45044a93c9d9a200c93cfd2c32d428c82a35f7b3d.
- Local artifact metadata: rc-pr303-20261103/RELEASE-MANIFEST.md. No provisioning keys or secrets are included.

## Physical iPhone 13 iOS 27.2 acceptance

Signed Development build of this exact source tested; **six of six XCTest cases passed**:

1. English Smart Exclusions and automatic-mode labels.
2. Hebrew Smart Exclusions and RTL.
3. Adaptive failed-host suggestion requires manual consent; no silent bypass.
4. Add site automatically discovers verified first-party subdomains; third-party hints are not approved.
5. Apex/www one grouped site; deleting one manual alias keeps sibling's child relationships.
6. Smart3 diagnostics badge; no silent exception.

No production proxy, VPN connection, Safari egress switching or synthetic saved profile was used. Local XCTest bundle: /private/tmp/apl-ios-020-pr303-physical-ui-20261103.xcresult.

## Reversible device QA

Before testing, backed up iPhone's App Group (11 preference keys), app preferences (20 keys) and a locally available signed app. After tests, reinstalled previously signed Development build 0.2.0 (48), **restored all 31 preferences** and verified per-key SHA256 identity with pre-test state. Neither saved proxy credentials nor profile values appeared in logs. The distribution archive is not installable directly on an unmanaged iPhone through devicectl; a properly Development-signed app was used. The restored Development executable was built on Nov 1, not proven byte-identical to the pre-test Nov 2–3 executable. For hands-on preview of the newest UI, install its separate Development build after explicit QA state preparation.

Private backups stay on Mac mini: /Users/master/Library/Application Support/Arvectum/ios-020-release-readiness-20261103/

## Source and language checks

- 131/131 Swift Core PASS.
- 147/147 iOS Python source-contract tests, plus 73 subtests PASS. Four stale expectations were corrected for historical 50-language coverage vs current 64 and a pinned flow-patch contract; no safety check weakened.
- 64/64 Apple .strings catalogs parse, six new Smart Exclusions controls localized into 64 languages, 24 faulty financial interpretations of Saving corrected.
- Three GitHub Mobile iOS personal runs on upstream PR #303 succeeded: 41616519259, 41616344000 and 41616290078.
- The historical October 30 seven-state Home/Banner matrix contains 50 observed locales, not fabricated entries for the 14 new ones.

## Remaining release decisions

The original Smart3 requirement was automatic Safari A -> auth.A proxy failure -> independently proven no-proxy route for exactly auth.A, without bypassing unrelated hosts on a shared CDN IP. Consumer iOS Packet Tunnel routing exclusions operate on IP/subnet, not hostname. MDM per-app excludedDomains are unsuitable for ordinary consumer distribution; Wi-Fi TLS evidence does not prove Safari direct egress. See docs/APL_IOS_020_EXACT_HOST_DIRECT_PLATFORM_GATE_2026-11-03.md.

This is a product/platform blocker. **Do not enable silent IP-wide bypass or claim full Smart3 shipped**. To submit this safe candidate, the owner must explicitly accept the narrower contract: automatic verified first-party dependencies, detected problem-domain suggestions, and manual third-party/auth approval. Otherwise leave the release blocked. Before any future App Store upload verify build-number availability and complete final App Store release decision. No App Store submission or changes to advertising/privacy were performed.
