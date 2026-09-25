# Arvectum Proxy Launcher — canonical roadmap

Updated: 2026-09-25
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Canonical branch: `main`  
Current stable product line: 0.2.16 — public release for Windows x64, Astra Linux 1.8 x86-64, RED OS 8.0.3 x86-64, generic Linux x86-64 AppImage and Developer ID-signed/notarized macOS Apple Silicon/Intel DMGs

Status legend: **DONE**, **PUBLISHED**, **CURRENT**, **READY NOW**, **READY**, **IMPLEMENTED**, **PARTIAL**, **HUMAN/LEGAL PENDING**, **STOP-GATE**, **PAUSED**, **DEFERRED**, **FUTURE**.

## 0. Repository authority and release baseline

- **DONE** — source/history/tags were recovered into `arvectum2/proxy-launcher`; `main` is the canonical integration branch.
- **DONE** — current governance, installer/support and repository-identity references are normalized to the canonical slug without rewriting historical provenance.
- **DONE** — GitVerse mirror logic is owner-independent on the GitHub side and current GitHub/GitVerse release mirroring is operational.
- **DONE** — exact-SHA GitHub Actions evidence was rebuilt in the canonical repository for Windows portable, Windows installer/Gate R6, SAST, SBOM, provenance and release evidence.
- **DONE** — `main` protection is governed by the active `Protect main` ruleset; PR + required `build` enforcement and negative merge acceptance have been proven.
- **DONE** — stale Windows PowerShell 5.1 signing-chain encoding contract was corrected in PR #43; `Windows Russian-first Production Signing` is green again without changing production signing behavior.
- **MIGRATION CLOSED** — the `arvectum1 -> arvectum2` repository migration is no longer an active project gate.

Historical repository identifiers remain valid only inside explicit provenance, closed acceptance, immutable baseline or historical workflow material. They are not current operational authorities.

## 1. Current stable product line

- **CURRENT / PUBLISHED — v0.2.16** (published 2026-09-25): Windows x64 Setup + portable ZIP, Astra Linux x86-64 DEB, RED OS 8.0.3 x86-64 RPM, generic Linux x86-64 AppImage, Developer ID-signed/notarized macOS Apple Silicon + Intel DMGs, plus SHA256SUMS.txt.
- **EXACT RELEASE OBJECT** — immutable v0.2.16 annotated tag/release points to `6799297bf1492d352ca9d78a0a49b2adf3345d2a`; GitHub asset digests, exact-SHA Release Evidence Package, Developer ID/notarization evidence and GitVerse public payload parity were verified.
- **POST-RELEASE METADATA ONLY** — any main commits after the v0.2.16 tag are documentation/checkpoint reconciliation only unless a later product task explicitly changes the product version.
- **v0.2.11** (published 2026-09-20) carried the Windows PAC/WPAD isolation fix and macOS Safari/CONNECT routing hardening.
- **v0.2.12** publishes the verified macOS long-sleep recovery and Android long-sleep/foreground VPN reconciliation while preserving immutable v0.2.11.
- **CURRENT SAFETY CONTRACT** — Windows rollback/recovery retains saved-or-Arvectum ownership/fail-closed semantics; Astra/Fly and RED OS/KDE real-host acceptance remain valid unless a material platform/recovery change requires rerun.
- **DONE / MAC PHYSICAL** — the v0.2.12 macOS long-sleep fix has real MacBook acceptance evidence: roughly 96 seconds Maintenance Sleep recovered without disabling APL or restarting the browser, with fresh CONNECT 200 after wake.
- **DONE / MAC TEST DISTRIBUTION** — `v0.2.10-macos-test.1` and `v0.2.10-macos-test.2` arm64 prereleases exist for dogfood. They are not the stable public macOS lane and do not imply Developer ID/notarization.
- **HISTORICAL ANCHOR** — v0.2.5 remains the first physically sealed Windows CFA-safe baseline and immutable provenance anchor.
- **HISTORICAL PROGRESSION** — v0.2.6 Windows+Astra; v0.2.7 RED OS; v0.2.8 Linux recovery hardening; v0.2.9 Windows recovery symmetry; v0.2.10 AppImage promotion; v0.2.11 PAC/WPAD + Safari routing fixes; v0.2.12 long-sleep recovery.

Current canonical main verified before this roadmap update: e843ab54b596eea622494fb3283af881e71826a8.
## 2. Russian-first release trust and Windows public trust

- **DONE** — APL-REL-010 real Rutoken/CryptoPro detached-signature POC and the Russian release-evidence architecture.
- **DONE / HISTORICAL EVIDENCE** — company УКЭП/CryptoPro remains RELEASE-EVIDENCE-ONLY; it is not Microsoft Authenticode/SmartScreen publisher trust.
- **DONE** — APL-REL-011/012/013 release manifest, verification UX and fail-closed Russian production release gate.
- **CURRENT PUBLIC RELEASE** — v0.2.16 is published without native Windows Authenticode; macOS Developer ID/notarization is a separate platform trust path.
- **READY FOR REVIEW REFRESH — issue #30, PR #161** — #161 is the latest substantive APL-REL-016 packet, but it became stale after later unsigned releases. With immutable v0.2.16 now public, refresh/rebase from current main and make **v0.2.17+** the first eligible future native Authenticode/public-trust release.
- **SUPERSEDED REVIEW HISTORY** — PRs #132 and #157 preserve older v0.2.10/v0.2.12-era preparation but are not the current packet.
- **OWNER GATE** — after refresh, provider/certificate selection, spend, key custody, packet merge as an approved decision, production signing and release remain Owner-reserved.
- **RULE** — never retrofit embedded signing into an immutable published release; every trust change belongs to a new version.

## 3. IP / legal / sovereignty

- **DONE** — APL-IP-002 platform sovereignty audits.
- **DONE** — APL-IP-003 canonical source refactor, Slices 1–23.
- **DONE** — APL-IP-004 promoted-artifact third-party license bundle engineering.
- **[Web] DONE — post-APL-IP-004 review reconciliation** — historical governance anchor remains candidate `ef9846e151a2e4e7046169e0787603969018cc97`; later v0.2.9 filing evidence does not rewrite that historical review.
- **HISTORICAL CONTRACT — CONDITIONAL / POST-APL-IP-004 ENGINEERING RECONCILED / HUMAN-LEGAL PENDING.** This phrase is retained solely for the historical clean-IP/legal-baseline contract; it does not mean the current registry filing-evidence packet is blocked.
- **[Web after explicit APPROVED] — create governed clean-IP baseline/tag** only if a distinct clean-IP/legal-baseline action is deliberately reopened.
- **DONE FOR CURRENT FILING EVIDENCE — APL-IP-001 / v0.2.9.**
- **HISTORICAL ANCHOR** — v0.2.5 remains the first physically sealed Windows CFA-safe IP/provenance baseline; its source/tag/artifact evidence and 2026-09-14 packet are preserved and are not rewritten.
- **DONE / EXACT-OBJECT ENGINEERING** — accepted v0.2.9 source commit `ca7c1019...`, source tree `55f2d50f...`, immutable tag commit `d13d9dac...` and promoted release-package digests are governed.
- **DONE / EXACT-TREE EVIDENCE** — provenance run `35255499712` and CycloneDX SBOM run `35255499669` bind to the exact released source tree.
- **DONE / ENGINEERING DRIFT RECONCILIATION** — material v0.2.5 -> v0.2.9 evolution is classified across Astra/Linux, RED OS/RPM, Linux recovery and Windows rollback-ownership slices.
- **DONE / OWNER FACTS** — the actual 2026-09-14 private sole-participant/rightsholder decision was reviewed; it identifies Arvectum Proxy Launcher without a version number, transfers the exclusive right in full and authorizes modification/reworking. Current Rospatent, corporate/Russian-control and human creative-control facts were confirmed by the Owner.
- **v0.2.9 HISTORICAL SCOPE** — Windows Setup + portable, Astra DEB and RED OS RPM. Owner directive 2026-09-18 separately admits AppImage for the next release; immutable v0.2.9 evidence is not rewritten.
- **PROCESS CORRECTION** — the previously prepared R-1B two-party/self-signing future-rights agreement is not a mandatory APL-IP-001 or registry-filing step. It is retained only as optional external legal hardening for the residual question of later human-authored copyrightable contributions. Do not reintroduce it as a blocker without new Owner/legal input.
- **RULE** — repository evidence is not a legal opinion. If the registry/expert or external counsel specifically requests a stronger chain-of-title instrument for later contributions, handle that as a targeted legal-hardening task rather than per-version compliance ritual.

Canonical current records: `docs/APL_IP_001_V0_2_9_SIGNOFF.md`, `docs/evidence/APL_IP_001_V0_2_9_CANDIDATE_RECONCILIATION_2026-09-18.md`, `docs/evidence/APL_IP_001_V0_2_9_OWNER_FACT_CONFIRMATION_2026-09-18.md`. Historical v0.2.5 records remain evidence.

## 4. Linux / Astra Linux

- **DONE** — APL-LNX-001..009 engineering: environment detection, NetworkManager preflight, capability/PolicyKit UX, autostart, diagnostics, Debian packaging and CI acceptance.
- **DONE / PHYSICAL PASS** — APL-LNX-010 / Gate R8 on Astra Linux Special Edition 1.8/Fly. Real-host evidence covers install, GUI/runtime, NetworkManager enable/disable, exact rollback, crash/reboot recovery, autostart, package lifecycle, diagnostics/privacy and cleanup.
- **DONE** — APL-LNX-011 fixed Firefox system-proxy behavior on Astra/Fly and was closed by PR #71/#72.
- **CURRENT RELEASE** — v0.2.16 publishes Arvectum-Proxy-Launcher-0.2.16-astra-linux-amd64.deb; v0.2.9 remains the governed registry-filing evidence baseline.
- **PROMOTED LANE** — Debian .deb remains the preferred Astra/Linux package.
- **PROMOTED FOR NEXT RELEASE** — the x86_64 AppImage lane uses the same canonical Linux frozen executable, hash-pinned appimagetool/type-2 runtime, embedded runtime/third-party notices, exact-main CI reuse and release checksum coverage. `v0.2.9` remains unchanged.
## 5. Russian Software Register / APL-REG-001

This is an active compliance/filing workstream, but repository dossier preparation is now substantially complete.

- **DECIDED WORKING CLASS** — 02.02 — Программы обслуживания, subject to live classifier/law recheck immediately before filing.
- **DONE / PHYSICAL** — first trusted-OS acceptance record: Astra Linux SE 1.8.
- **DONE / PHYSICAL** — second trusted-OS acceptance record: RED OS 8.0.3 Standard Desktop x86-64, merged in PR #83.
- **DONE** — APL-REG-001D filing-grade documentation dossier for v0.2.9 merged in PR #95; final checkpoint PR #96 records 6/6 focused dossier tests and 10/10 exact-head GitHub workflows successful.
- **CURRENT LEGAL TIMING BASELINE** — under the official baseline rechecked on 2026-09-17, the two-trusted-OS condition for class 02.02 starts on **2027-01-01**. Existing Astra/RED acceptance is retained as future-proof compatibility evidence; exact v0.2.9 reruns are preferred but are not represented as a current 2026 filing prerequisite.
- **PRE-SUBMISSION / HOLD** — external filing is blocked on real HUMAN/PRIVATE/PHYSICAL evidence: exclusive-right/corporate/Russian-control chain, applicable foreign-payment/accounting evidence, APL-REG-001B physical sovereign lifecycle proof, factual Russian support/modification contacts, final exact-v0.2.9 Russian-GUI visual review, signer authority/qualified electronic signature, and a live law/portal recheck.
- **HARD STOP** — automation must not sign or submit the Ministry/registry application or ingest УКЭП/private-key material.

Canonical dossier: docs/registry/. Canonical pre-submission gate: docs/registry/APL_REG_001F_PRE_SUBMISSION_AUDIT.md.
## 6. macOS

- **DONE** — APL-MAC-001..008 engineering/acceptance track and Gate R9 evidence retained.
- **DONE / TEST DISTRIBUTION** — arm64 prereleases `v0.2.10-macos-test.1` and `v0.2.10-macos-test.2` were published for dogfood and mirrored with checksum parity.
- **DONE / ROUTING + WAKE HARDENING** — PRs #141/#143/#146/#149 plus later v0.2.14/v0.2.15 recovery work close the current direct-distribution routing/sleep baseline.
- **PRODUCTION DISTRIBUTION — DONE / PUBLISHED v0.2.16** — exact-main ARM64/Intel packages were promoted through the Arvectum Mac mini, signed with Developer ID Application, Apple-notarized/stapled, Gatekeeper-verified, published and mirrored with payload parity.
- **MAC APP STORE — IN PROGRESS / draft PR #175 / target v0.2.17.** The Store lane is separate and must not mutate or replace the direct v0.2.16 Developer ID/notarized DMG channel.
  - Physical sandbox smoke proved the direct `/usr/sbin/networksetup` backend is incompatible with App Sandbox: unsandboxed read PASS; sandboxed read exited 133.
  - Canonical Store architecture is now a separate Mac Catalyst app `ru.arvectum.proxylauncher.macos` + PacketTunnel extension `ru.arvectum.proxylauncher.macos.PacketTunnel` + App Group `group.ru.arvectum.proxylauncher.macos`.
  - PR #175 implements the isolated Catalyst/PacketTunnel lane using the proven Swift/NetworkExtension transport; Mac App Store contract tests are **6/6 PASS**, and unsigned ARM64 Catalyst Debug build passes.
  - Current technical stage: create/register Apple identifiers/capabilities and development/App Store provisioning profiles for the new app + extension, then run signed physical Mac mini build/tunnel smoke.
  - Signed automatic-provisioning already reached Apple signing and failed only because the new identifiers lack development profiles/Apple Account provisioning in Xcode.
- **MANDATORY HELP UX BEFORE FIRST MAC APP STORE SUBMISSION.** PR #175 started before this later roadmap amendment, so its branch checkpoint is not sufficient by itself: before submission it must reconcile with current main and add this Help contract.
  - Standard macOS **Help** menu opens a bundled offline help surface; no “No help is available for Arvectum Proxy Launcher” system response.
  - Offline sections: **Getting Started**, **status meanings**, **proxy formats**, **Troubleshooting**, **About & Privacy**.
  - Footer/about: running version, **© Arvectum LLC**, **View on GitHub**, **Release Notes**, **Report a Problem**.
  - **Release Notes** targets `https://github.com/arvectum2/proxy-launcher/releases/latest`, not a hard-coded version.
  - Help remains useful offline; online links are secondary.
  - **Check for Updates** is channel-aware: direct Developer ID builds may later use a direct/GitHub path, while Mac App Store builds must rely on App Store updates and not ship a competing self-updater.
- **OPTIONAL FUTURE** — keep `.app`/DMG as the normal direct macOS distribution lane; add a separate portable form only if it provides real benefit without weakening recovery/update semantics.

## 7. Per-application routing — next desktop product capability

- **DONE** — APL-ROUTE-001 platform-neutral routing-rule model.
- **DONE** — APL-ROUTE-002 per-platform feasibility matrix.
- **AUTONOMOUS COMPLETE / LOCAL-NATIVE PENDING** — APL-ROUTE-003 Windows control-plane prototype.
- **DONE** — APL-ROUTE-004 durable ownership/recovery/security journal.
- **CURRENT OWNER PACKET — PR #144** — supersedes stale PR #68 and carries the production enforcement decision packet; exact-head checks were green for its current content.
- **REFRESH NEEDED BEFORE FINAL OWNER DECISION** — #144 is written against the immutable v0.2.12 saved-or-Arvectum baseline. Reconcile it to **v0.2.16/current-main** recovery semantics and the current APL-REL-016 dependency before Owner review.
- **STOP-GATE** — the technical recommendation remains an Arvectum-owned WFP ALE callout + narrow privileged service + local proxy, but architecture selection remains Owner/Product Owner reserved.
- **AFTER APPROVAL** — implementation requires privileged Windows host work, ownership/recovery/security acceptance and a new product version.

## 8. Mobile applications

### Android — public 0.1.19 / current-main 0.1.31 friend-test

- **DONE — APL-MOB-001 baseline.** Native VpnService/TUN transport, manual profiles and one-button mobile UX are physically established.
- **DONE — APL-MOB-002 pool/failover.** Automatic proxy health/failover and physical-network handoff are accepted.
- **DONE / PUBLIC — APL-MOB-003 site exclusions.** The physically accepted site-exclusion UX/routing was integrated via PR #130 and published as `android-v0.1.19` on 2026-09-19.
- **DONE / CURRENT MAIN — sleep recovery + free RU/US gateway.** PRs #147/#148 add long-sleep reconciliation and server-backed free locations. Supplier credentials stay server-side.
- **CURRENT MAIN / FRIEND-TEST CANDIDATE — Android 0.1.31 (versionCode 32).** Exact-head Android/gateway/security checks pass; gateway tests 13/13 pass; RU/US checks and US 15/15 soak pass. **No public android-v0.1.31 release tag exists.**
- **PUBLIC-SCALE GATE** — add per-install quotas/rate limiting/anti-abuse controls before broad anonymous rollout.
- **PLANNED / OWNER-GATED — APL-MOB-004 monetization + dual distribution.** Advertising/private-no-ads distribution remains separate from free-proxy functionality and starts only after explicit Owner priority + package/update-identity decision.

### iOS — 0.1.19 App Store review wait

- **PHYSICAL PASS / CODE MERGED — PR #135.** SwiftUI + NetworkExtension Packet Tunnel parity is implemented, physically accepted on iPhone and merged to main.
- **APP STORE SUBMISSION COMPLETE.** Final Apple Distribution IPA 0.1.19 build 21 passed Apple validation and upload, processed successfully and is attached to App Store version 0.1.19.
- **CURRENT APPLE STATE — WAITING FOR REVIEW.** Version 0.1.19 build 21 was submitted to App Review; canonical checkpoint records **1 Item Submitted / Waiting for Review**.
- **PRIVACY/STORE TRUTH** — Data Not Collected; no ads, analytics, Arvectum cloud backend or per-app routing in this release. Required first-use VPN disclosure, privacy manifests, public privacy/support pages, metadata, screenshots and review notes are complete.
- **CREDENTIAL HYGIENE DONE** — temporary App Store Connect API keys used for upload/submission were revoked and local temporary key files/helpers removed.
- **BOUNDARY** — the app is **not yet claimed public/live**. Do not rebuild, re-upload, withdraw or resubmit unless Apple returns a concrete review issue or the Owner requests a change.

## 9. Currently available workstreams

1. **[Desktop release] v0.2.16 — PUBLISHED / IMMUTABLE.** Exact release SHA `6799297bf1492d352ca9d78a0a49b2adf3345d2a`; macOS Apple Silicon/Intel assets are Developer ID-signed and Apple-notarized.
2. **[Android/free gateway] 0.1.31 — MERGED FRIEND-TEST BASELINE / NOT PUBLIC RELEASE.** RU/US server-backed locations are live; broad-public anti-abuse/quota hardening remains a future gate.
3. **[IP/legal] APL-IP-001 exact v0.2.9 filing-evidence packet — DONE.** Do not silently re-scope registry evidence to later releases.
4. **[Windows trust / REVIEW] APL-REL-016 — READY FOR REFRESH.** Latest substantive PR is #161; refresh to immutable v0.2.16 / first eligible v0.2.17+, then stop at Owner review.
5. **[Registry infrastructure / HUMAN] APL-REG-001B — BLOCKED UNTIL PHYSICAL RUSSIAN LIFECYCLE EVIDENCE EXISTS.**
6. **[Per-app routing / OWNER] production architecture — CURRENT PR #144.** Reconcile its v0.2.12 baseline to v0.2.16/current-main semantics; final architecture choice remains Owner-reserved.
7. **[Registry filing / HUMAN] APL-REG-001E/F — PRE-SUBMISSION HOLD.** Repository dossier is done; private/accounting/infrastructure/support/signature/live-portal evidence remains.
8. **[APL-MOB-004 / OWNER] advertising + public/private Android distribution — PLANNED.**
9. **[macOS direct production distribution] — DONE / PUBLISHED v0.2.16.**
10. **[iOS / APPLE] 0.1.19 build 21 — SUBMITTED / WAITING FOR REVIEW.** No repo action unless Apple returns a concrete issue or Owner requests a change.
11. **[macOS App Store / HUMAN] PR #175 — IN PROGRESS / target v0.2.17.** Catalyst + PacketTunnel architecture is implemented; current stage is Apple identifiers/provisioning then signed physical smoke. Before submission, branch must reconcile the later mandatory offline Help UX amendment.

### Repository-hygiene note

Open PRs #81/#103/#132/#157 are superseded Windows-trust preparation history; PR #161 is the latest substantive but version-stale packet to refresh. PR #68 is superseded by current per-app PR #144. Original MOB-003 PR #125 is superseded by merged #130. Historical Windows rollback and RED OS preparation PRs remain non-authoritative where later merged work exists.

### Execution order

- Do not reopen completed v0.2.16 direct macOS production-signing/notarization acceptance.
- **Active HUMAN work already underway:** Mac App Store PR #175. Preserve its separate Catalyst/PacketTunnel architecture and reconcile the later mandatory Help UX before submission.
- **First independent safe REVIEW lane when not conflicting with active App Store work:** refresh APL-REL-016 PR #161 to immutable v0.2.16 / first eligible v0.2.17+, then stop at Owner review.
- **Next independent preparation lane:** refresh per-app PR #144 to v0.2.16/current-main semantics, then stop before Owner architecture selection.
- **External wait:** iOS 0.1.19 build 21 is Waiting for Review; do not churn the binary/metadata while Apple review is pending.
- Android 0.1.31 public release, gateway public-scale anti-abuse and APL-MOB-004 advertising/private distribution remain explicit Owner/HUMAN gates.
- External Ministry/registry submission remains outside automation.

## 10. Platform / distribution matrix

| Platform / form | Current state | Next gate |
| --- | --- | --- |
| Windows installer | **PUBLISHED v0.2.16** | Maintenance; Windows Authenticode remains a separate trust track |
| Windows portable | **PUBLISHED v0.2.16** | Maintenance / future feature release |
| Astra Linux .deb | **PUBLISHED v0.2.16 / PHYSICAL BASELINE PROVEN** | Rerun physical acceptance only for material platform/recovery or filing changes |
| RED OS .rpm | **PUBLISHED v0.2.16 / PHYSICAL BASELINE PROVEN** | Rerun physical acceptance only for material platform/recovery or filing changes |
| Linux AppImage | **PUBLISHED v0.2.16** | Maintain governed runtime/license/release parity |
| macOS .app / DMG | **PUBLISHED v0.2.16 / DEVELOPER ID + NOTARIZED** | Maintain exact-main ephemeral signing/notarization gate for future direct macOS releases |
| macOS Mac App Store | **IN PROGRESS / PR #175 / target v0.2.17** | Apple identifiers/profiles → signed physical Catalyst/PacketTunnel smoke → mandatory offline Help UX reconciliation → App Store validation/submission |
| Android | **0.1.19 PUBLIC / 0.1.31 MAIN FRIEND-TEST / FREE RU+US LIVE** | Public 0.1.31 release is separate; add anti-abuse before large rollout; MOB-004 remains Owner-gated |
| iOS | **0.1.19 build 21 SUBMITTED / WAITING FOR REVIEW** | Wait for Apple; act only on concrete review result or Owner change request |

## Completion discipline

Do not substitute CI for physical App Control/Astra/РЕД ОС/mobile-device evidence, detached Russian release evidence for Microsoft native Windows publisher trust, or automation for human/legal decisions. Do not rewrite historical repository identities where they are part of provenance. Do not retarget immutable tags or replace published release assets in place. A documentation-only commit does not create a new product candidate. Current operational references must resolve to `arvectum2/proxy-launcher`.
