# iOS 0.2.0 (48) — public App Store release, 4 November 2026

## Release identity and Apple

- App ID 6816013574; bundle `ru.arvectum.proxylauncher.ios`; version 0.2.0 (build 48).
- Previous **0.1.41(46) READY_FOR_SALE**, independently confirmed 2026-11-04 by authenticated App Store Connect API. Its binary and privacy declarations were not changed.
- New App Store version ID `e8d364e7-07c9-4ba2-bece-862f7905320a` created with `AFTER_APPROVAL`.
- Distribution IPA source is verified commit `f0a93f8addb4b61961e9c53c885871a563aef9c6` (the later checkpoint-only commit `e54a9051` does not change shipped binaries).
- Signed IPA: `/private/tmp/APL-iOS-020-Smart3-DualStack-Handoff-RSYA-20261104-export/Arvectum Proxy Launcher.ipa` SHA256 `7e716fad3a946fc4c7623acef57fe174939eae9ddf612617358ec5f1f9fe60fe`, size 9,070,959 bytes. Apple Distribution signatures: main app + PacketTunnel PASS; 64 locale bundles, YandexMobileAds binary + 228 SKAdNetwork items PASS.
- Apple ContentDelivery upload `UPLOAD SUCCEEDED`; delivery/build ID `b60b4825-d72f-455e-a681-2941e4aca438`. Apple API processing `VALID`, encryption declaration `usesNonExemptEncryption=false`, build attached to version 0.2.0.
- 47 App Store locale records inherited from published 0.1.41; 47 new localized What's New strings prepared in `mobile/ios/ASO/release_notes_020.tsv` and uploaded. Apple carried over 94 real screenshots from the prior version, independently confirmed all asset states `COMPLETE`. The three other offline ASO locale sources are not part of the 47 actual Apple version locales.
- Submission automation: `mobile/ios/ASO/release_020.py`; every mutation requires explicit `--confirm-version 0.2.0`. No privacy, existing ads, old versions or personal proxies are mutated.

## Functional evidence

- iOS Smart3 physical proof from 3–4 Nov: two proxy timeouts and independent physical TLS verification lead to exact-virtual-DNS-host TCP DIRECT, including originally stalled Safari HTTPS streams; a different hostname on a shared CDN IP remains PROXY.
- Hardware IPv4 and IPv6 validation, fallback after TLS first-record failure, two recovered original streams + fresh flow, raw-IP/DoH endpoints and QUIC/UDP fail-closed proxy path, revocation on physical path change, short-TTL expiry and network switch. Continuous migration of one existing TCP connection over Wi-Fi→LTE is **not** claimed.
- Physical iPhone proof of genuine primary Yandex banner and native advertisement impressions in an ordinary Release-compiled build; both active placements and SDK retained. Privacy questionnaire unchanged.
- Inherited physical QA: 6/6 Smart Exclusions UI on iPhone 13, full saved app preference restoration by SHA256, 64 UI languages, 16 deeper locale checks, XXL 11 locales, accessibility audit 0 findings, simulator 9/9.
- Swift Core 134 tests with two new frozen 0.1.41 Codable/organization compatibility fixtures; iOS source contract tests include 4 new checks of legacy App Group keys, Keychain service/access group, Codable raw values and additive encrypted backup. Historical Rust 17/17 and Python iOS 176/176 +73 subtests passed for unchanged production routing code.
- No new production Swift/Rust code changes were made in the release prep branch after the proven final signed IPA.

## Migration and remaining bounded risks

- The signed 0.1.41(46) IPA and release archive are present and identified; old and new app IDs, app-group entitlements and Keychain access-group identifiers agree. `profiles.v1`, UUID selection, backup selection, restore policy and legacy `site_exclusions` retain compatible representations. Older backups in `.aplbackup` format do not exist in 0.1.41; encrypted import/export is a new 0.2.0 feature and has independent codec tests.
- A source-reconstructed 0.1.41(46) simulator build was produced, signed for simulator and installed on an isolated iPhone 17 Pro (iOS 27.0). An eight-key **synthetic** old App Group fixture (profiles.v1 with two fake .invalid hosts, primary/selected UUIDs, Auto and restore policy, legacy site exclusions and app routing) was injected and SHA256-recorded. The same-bundle-ID signed 0.2.0(48) simulator build was installed **in place** without uninstall; version and build changed to 0.2.0(48), App Group container path remained identical, 8/8 synthetic saved values matched exact SHA256 before/after. This source-reconstructed simulator 0.1.41 is **not byte-identical** to Apple's distributed App Store build, and device Keychain credentials were neither seeded nor read. Accordingly, real distributed-binary 0.1.41→0.2.0 Keychain continuity on a normally signed disposable iPhone has not been independently proven. Frozen schema and Swift Codable tests PASS; no user's iPhone was downgraded.
- Independent human native-speaker certification is not available: safety-sensitive terminology underwent prior model-led editorial QA, and all 47 release notes have explicit new localization, but this is not an external translator sign-off.
- Apple NetworkExtension TN3120 warns about routing captured tunnel flows over another physical interface. The working consumer implementation has device evidence; **Apple App Review decides App Store acceptability**. We do not claim preliminary Apple approval or reverse engineer private Apple APIs.
- Screenshots inherited from 0.1.41 show actual unchanged introductory/privacy experiences but not the newest Smart3 settings view; additional marketing images can be updated separately if Apple requests changes.
- The signed IPA and Apple metadata are separate from GitHub integration. Historical dated roadmap items must not override this 4 November release account.

## Deferred product backlog (not required for iOS 0.2.0)

CloudKit exception sync, Proxifier-like common desktop routing engine, QRVPN-like hosted gateway, storefront coverage audit and native linguist certification are separate product/quality workstreams, not hidden unimplemented binary features.
