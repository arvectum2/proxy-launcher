# Step 4 — artifact-bound evidence and proposed release scope

Status: offline audit completed for the observed default artifact and pinned research inventory; **release blocked; owner scope approval and actual integration/acceptance pending**. Do not treat this as a new published version or authority to sign, merge, distribute notices, or upload. Current ordinary unsigned identity is still 0.2.0 (48); 0.3.0 is the target single release.

## Observed ordinary local artifact

Source HEAD `9f8a308e71f350b7cb9c9ceafc316c727a1995ba`, exact locked Swift package resolution, unsigned iPhoneOS Release build with link maps PASS. `Tools/audit_unsigned_release_linkage.py` checked app/extension version, copied extension hash, selected Rust archive versus Xcode build product, exact checkout commits and original Git license blobs. Local evidence in `native-artifacts/default-release-linkage-evidence-20261115`, manifest SHA-256 `3b740d6c632ef1a652a3143b0a94ea777889a336238c58553b6fa0b26c296de9`; ten notice hashes and both preserved raw link maps verified. No evidence is published; do not distribute vendor binaries or source without review.

| Component | Observed evidence | Open gate |
|---|---|---|
| Default tun2proxy v0.8.3 | Build input and archive SHA match `dda7ce82ff60d6b44a91d7c0ef145d6eeefddce0723580c073b560944781dfe8`; 264 imported archive object rows in map | Connected-UDP patched variant differs from the loopback-clean native research artifact. Need exact selected build graph and patch/source/license closure. No claim all graph dependencies survived linker dead stripping; absence by object name is not proof of absence. |
| YandexMobileAds 8.6.0 | Embedded framework, named link objects, pinned package LICENSE.txt | Original vendor binary terms, internal/transitive closure, SDK privacy and advertising acceptance review. |
| AppMetrica 6.7.1 | Named linked objects, three original notice files including FMDB and protobuf | Actual built component and embedded dependency review. |
| KSCrash 2.5.1 | Named linked objects, original LICENSE | Final artifact notice delivery review. |
| Google UMP 3.1.0; SwiftProtobuf 1.39.0; Tapjoy 14.8.0 | Resolved packages; no named object in app link-map table; five notice files across Google/SwiftProtobuf, none in Tapjoy checkout | Not established as shipped or absent; check opaque SDK/internal linkage, final selected targets and vendor terms before deciding obligations. |
| Native research | Pinned Xray/AWG/Rust inventories 344 original notice files, 3 MPL archives, 7 supplemental files, two unsigned lab executable hashes PASS | Not the default artifact or final SBOM. `tproxy-config` exact crate declares MIT, original copyright/notice missing. Public crates.io/docs.rs and upstream repository metadata agree with local declaration; no original attribution recovered. |

No notice absence is silently reclassified as compliant. The audit is evidence, not legal advice or clearance. Do not fabricate a copyright notice or assume a generic MIT template resolves the omission. Existing local research receipts are preserved independently.

## Release scope recommendation, not authorization

| Feature family | Current status | Release recommendation |
|---|---|---|
| Existing HTTP/HTTPS/SOCKS5, universal import, manual HTTPS subscriptions, backup, ads | Implemented in baseline; local regression/build accepted | Retain in unified candidate; final signed compatibility, ads/privacy and QA gates required. |
| WireGuard / VLESS / AWG1 | Scoped earlier physical20 fixtures; inactive integration contract and gated preview only; new source-built binary not accepted | Integrate actual provider/storage/UI under controlled candidate gates; no product claim until exact signed acceptance. |
| Smart Routing 4.0, native FIN, DNS/exclusion and network handoff behavior | Research contracts / scoped earlier receipts | Do not enable or advertise unsupported policies; require N1/N2 and exact artifact evidence. |
| CloudKit | Inactive account-bound review and UI; no entitlement | C1 and explicit private-container approval mandatory for inclusion. |
| Optional subscription refresh | Offline opt-in/foreground review policy only | Keep existing manual refresh; defer automatic network/production integration unless separately approved. |
| AWG2/AWG3 | Unsupported | Exclude from release claims. |

Chosen engineering priority: continue toward the single 0.3.0 release as originally requested, not a smaller public release. Do not silently narrow user-approved scope, bump the active identity, or substitute an earlier lab artifact for the final candidate. Remaining work is actual inactive integration of the provider/credential/UI path and exact selected dependency closure. Owner decisions are required for any scope reduction, legal/source distribution, signing and release. S1/K1/K2/X1/N1/N2/C1/R1 remain outstanding according to the acceptance runbook. No device or account action was taken.
