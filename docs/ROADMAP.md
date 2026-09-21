# Arvectum Proxy Launcher — canonical roadmap

Updated: 2026-09-21
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Canonical branch: `main`  
Current stable product line: 0.2.12 — public release for Windows x64, Astra Linux 1.8 x86-64, RED OS 8.0.3 x86-64 and generic Linux x86-64 AppImage

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

- **CURRENT / PUBLISHED — v0.2.12** (published 2026-09-21): Windows x64 Setup + portable ZIP, Astra Linux x86-64 DEB, RED OS 8.0.3 x86-64 RPM, generic Linux x86-64 AppImage, plus SHA256SUMS.txt.
- **EXACT RELEASE OBJECT** — immutable v0.2.12 tag/release points to `8d9a4e5913fa92b39f0f926004df6f1fd57f3bde`; GitHub asset checksums and GitVerse canonical payload parity were independently verified.
- **CURRENT MAIN IS AHEAD OF THE RELEASE** — canonical `main` is `df4478a70729e20f33b7a0d17476183423955576` after merged PR #148. The free-proxy gateway/Android 0.1.31 work is therefore **not** part of immutable desktop v0.2.12.
- **v0.2.11** (published 2026-09-20) carried the Windows PAC/WPAD isolation fix and macOS Safari/CONNECT routing hardening.
- **v0.2.12** publishes the verified macOS long-sleep recovery and Android long-sleep/foreground VPN reconciliation while preserving immutable v0.2.11.
- **CURRENT SAFETY CONTRACT** — Windows rollback/recovery retains saved-or-Arvectum ownership/fail-closed semantics; Astra/Fly and RED OS/KDE real-host acceptance remain valid unless a material platform/recovery change requires rerun.
- **DONE / MAC PHYSICAL** — the v0.2.12 macOS long-sleep fix has real MacBook acceptance evidence: roughly 96 seconds Maintenance Sleep recovered without disabling APL or restarting the browser, with fresh CONNECT 200 after wake.
- **DONE / MAC TEST DISTRIBUTION** — `v0.2.10-macos-test.1` and `v0.2.10-macos-test.2` arm64 prereleases exist for dogfood. They are not the stable public macOS lane and do not imply Developer ID/notarization.
- **HISTORICAL ANCHOR** — v0.2.5 remains the first physically sealed Windows CFA-safe baseline and immutable provenance anchor.
- **HISTORICAL PROGRESSION** — v0.2.6 Windows+Astra; v0.2.7 RED OS; v0.2.8 Linux recovery hardening; v0.2.9 Windows recovery symmetry; v0.2.10 AppImage promotion; v0.2.11 PAC/WPAD + Safari routing fixes; v0.2.12 long-sleep recovery.

Current canonical main verified for this roadmap refresh: df4478a70729e20f33b7a0d17476183423955576.
## 2. Russian-first release trust and Windows public trust

- **DONE** — APL-REL-010 real Rutoken/CryptoPro detached-signature POC and the Russian release-evidence architecture.
- **DONE / HISTORICAL EVIDENCE** — company УКЭП/CryptoPro remains RELEASE-EVIDENCE-ONLY; it is not Microsoft Authenticode/SmartScreen publisher trust.
- **DONE** — APL-REL-011/012/013 release manifest, verification UX and fail-closed Russian production release gate.
- **CURRENT PUBLIC RELEASE** — v0.2.12 is published without native Authenticode.
- **READY FOR REVIEW REFRESH — issue #30, PR #132** — PR #132's substantive research remains useful, but its immutable baseline/version boundary is stale: it targets v0.2.10 with v0.2.11+ as first eligible. Because v0.2.11 and v0.2.12 are now public and unsigned, refresh/rebase the packet to v0.2.12 and make **v0.2.13+** the first eligible future embedded-signing release.
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
- **CURRENT RELEASE** — v0.2.9 publishes Arvectum-Proxy-Launcher-0.2.9-astra-linux-amd64.deb.
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
- **DONE / ROUTING HARDENING** — PRs #141/#143 hardened upstream failover and Safari CONNECT behavior before v0.2.11.
- **DONE / LONG-SLEEP RECOVERY** — PRs #146/#149 resolved the macOS sleep/wake regression; the final v0.2.12 behavior was physically accepted on a MacBook and is part of the desktop source release.
- **PRODUCTION DISTRIBUTION DEFERRED** — stable public macOS DMG remains outside the desktop release set until Apple Developer ID signing/notarization is deliberately activated.
- **OPTIONAL FUTURE** — keep `.app`/DMG as the normal macOS distribution lane; add a separate portable form only if it provides a real operational benefit without weakening recovery/update semantics.

## 7. Per-application routing — next desktop product capability

- **DONE** — APL-ROUTE-001 platform-neutral routing-rule model.
- **DONE** — APL-ROUTE-002 per-platform feasibility matrix.
- **AUTONOMOUS COMPLETE / LOCAL-NATIVE PENDING** — APL-ROUTE-003 Windows control-plane prototype.
- **DONE** — APL-ROUTE-004 durable ownership/recovery/security journal.
- **CURRENT PREPARATION — PR #144** — PR #144 supersedes stale PR #68 and carries the Owner decision packet without replaying obsolete agent metadata. Exact-head repository checks are green.
- **REFRESH NEEDED BEFORE FINAL OWNER DECISION** — PR #144 still names the v0.2.10 saved-or-Arvectum baseline. Reconcile it to immutable v0.2.12/current-main recovery semantics, including the now-current APL-REL-016 signing dependency.
- **STOP-GATE** — the packet may recommend the Arvectum-owned WFP ALE callout + privileged service + local proxy path, but architecture selection remains Owner/Product Owner reserved.
- **AFTER APPROVAL** — implementation requires privileged Windows host work, ownership/recovery/security acceptance and a new product version.

## 8. Mobile applications

### Android — public 0.1.19 / current-main 0.1.31 friend-test

- **DONE — APL-MOB-001 baseline.** Native VpnService/TUN transport, manual profiles and one-button mobile UX are physically established.
- **DONE — APL-MOB-002 pool/failover.** Automatic proxy health/failover and physical-network handoff are accepted.
- **DONE / PUBLIC — APL-MOB-003 site exclusions.** The physically accepted site-exclusion UX/routing was integrated via PR #130 and published as `android-v0.1.19` on 2026-09-19.
- **DONE / SLEEP RECOVERY IN CURRENT MAIN** — PR #147 added foreground/service reconciliation after long Android sleep; the initial fix bumped the candidate to 0.1.20 and is included in the later 0.1.31 main baseline.
- **DONE / LIVE FRIEND-TEST INFRA — free RU/US gateway.** PR #148 merged the server-side gateway and Android integration. Supplier proxy credentials remain server-side; clients receive only short-lived location-bound Arvectum gateway credentials.
- **DONE / LIVE CONNECTIVITY EVIDENCE** — Mac mini launchd gateway + public TLS ingress are live; real RU→RU and US→US checks pass. The gateway public API exposes only location metadata, not supplier credentials.
- **CURRENT MAIN / FRIEND-TEST CANDIDATE — Android 0.1.31 (versionCode 32).** Exact-head Android/gateway/security checks pass; lint has 0 errors; gateway tests 13/13 pass; RU/US checks and a US 15/15 soak pass. **No public android-v0.1.31 release tag exists.**
- **PUBLIC-SCALE GATE** — current gateway is suitable for controlled friend testing, not a large anonymous rollout. Add per-install quotas/rate limiting/anti-abuse controls before broad public distribution.
- **PLANNED / OWNER-GATED — APL-MOB-004 monetization + dual distribution.** Advertising/private-no-ads distribution is a separate track from the already implemented free gateway. Start only after explicit Owner priority and private package/update-identity decision.
  - Public Android channel: GitHub, GitVerse, Arvectum site and RuStore with ads only after a new monetized release.
  - Initial ad target: Yandex Mobile Ads / App Open with first-launch grace, frequency limiting, fail-open behavior and privacy/consent documentation.
  - Private no-ads artifact should come from the same codebase via build configuration/flavor and remain outside the public GitHub release surface.

### iOS — personal-use engineering lane

- **IN PROGRESS / DRAFT PR #135** — a SwiftUI + NetworkExtension Packet Tunnel personal-use parity baseline exists, based on accepted Android 0.1.19 semantics: Auto/manual selection, health/failover, Keychain/App Group storage, HTTP/SOCKS5/HTTPS relay and site exclusions.
- **ENGINEERING CHECKS** — plutil, XcodeGen project generation, Swift core build and Swift source parsing are recorded PASS on the branch.
- **HUMAN GATE** — full Xcode/XCTest/device build, Apple signing/provisioning and physical iPhone installation are not complete.
- **BOUNDARY** — this is personal-use only. No App Store/public distribution, no committed certificates/provisioning profiles and no per-app-routing promise beyond platform capabilities.

## 9. Currently available workstreams

1. **[Desktop release] v0.2.12 — PUBLISHED / IMMUTABLE.** Exact release SHA `8d9a4e5913fa92b39f0f926004df6f1fd57f3bde`; current `main` is ahead via free-gateway/mobile work.
2. **[Android/free gateway] 0.1.31 — MERGED FRIEND-TEST BASELINE / NOT PUBLIC RELEASE.** RU/US server-backed locations are live and secrets stay server-side; broad-public anti-abuse/quota hardening remains a future gate.
3. **[IP/legal] APL-IP-001 exact v0.2.9 filing-evidence packet — DONE.** Do not silently re-scope registry evidence to v0.2.12.
4. **[Windows trust / REVIEW] APL-REL-016 — READY FOR REFRESH.** Rebase/replace PR #132 to immutable v0.2.12 and first eligible v0.2.13+, then stop at Owner review.
5. **[Registry infrastructure / HUMAN] APL-REG-001B — BLOCKED UNTIL PHYSICAL RUSSIAN LIFECYCLE EVIDENCE EXISTS.**
6. **[Per-app routing / OWNER] production architecture — CURRENT PR #144.** Refresh its v0.2.10 baseline wording to v0.2.12/current-main semantics; final architecture choice remains an Owner stop-gate.
7. **[Registry filing / HUMAN] APL-REG-001E/F — PRE-SUBMISSION HOLD.** Repository dossier is done; private/accounting/infrastructure/support/signature/live-portal evidence remains.
8. **[APL-MOB-004 / OWNER] advertising + public/private Android distribution — PLANNED.** Free-proxy work does not authorize the ad SDK/provider/private-package lane.
9. **[macOS production distribution] — DEFERRED.** Long-sleep behavior is fixed/accepted, but Apple Developer ID signing/notarization remains non-primary.
10. **[iOS / HUMAN] draft PR #135 — ACTIVE PERSONAL-USE ENGINEERING.** Physical signing/install/Xcode device validation remains open; App Store distribution is not in scope.

### Repository-hygiene note

Open PRs #81/#103 are superseded Windows-trust preparations; PR #132 is the current but version-stale trust packet to refresh. PR #68 is superseded by current per-app preparation PR #144. Original MOB-003 PR #125 is superseded by merged #130. Historical Windows rollback and RED OS preparation PRs remain non-authoritative where later merged work exists.

### Execution order

- The canonical current task is completed v0.2.12 release work; do not reopen it.
- **First safe autonomous REVIEW lane:** refresh APL-REL-016 from PR #132 to current immutable v0.2.12 / first eligible v0.2.13+, then stop at Owner review.
- **Next safe preparation lane:** reconcile per-app routing PR #144 from v0.2.10 wording to v0.2.12/current-main recovery semantics, then stop before Owner architecture selection.
- Android 0.1.31 public release, gateway public-scale anti-abuse, APL-MOB-004 advertising/private distribution and iOS signing/device work remain explicit Owner/HUMAN gates.
- External Ministry/registry submission remains outside automation.

## 10. Platform / distribution matrix

| Platform / form | Current state | Next gate |
| --- | --- | --- |
| Windows installer | **PUBLISHED v0.2.12** | Maintenance; APL-REL-016 targets a future v0.2.13+ signed release |
| Windows portable | **PUBLISHED v0.2.12** | Maintenance / future feature release |
| Astra Linux .deb | **PUBLISHED v0.2.12 / PHYSICAL BASELINE PROVEN** | Rerun physical acceptance only for material platform/recovery or filing changes |
| RED OS .rpm | **PUBLISHED v0.2.12 / PHYSICAL BASELINE PROVEN** | Rerun physical acceptance only for material platform/recovery or filing changes |
| Linux AppImage | **PUBLISHED v0.2.12** | Maintain governed runtime/license/release parity |
| macOS .app / DMG | **TEST PRERELEASES test.1/test.2 / v0.2.12 SOURCE FIXES / PROD DEFERRED** | Apple Developer ID signing/notarization when prioritized |
| Android | **0.1.19 PUBLIC / 0.1.31 MAIN FRIEND-TEST / FREE RU+US LIVE** | Public 0.1.31 release is separate; add anti-abuse before large rollout; MOB-004 remains Owner-gated |
| iOS | **DEFERRED** | Start after Android product semantics / entitlement path |

## Completion discipline

Do not substitute CI for physical App Control/Astra/РЕД ОС/mobile-device evidence, detached Russian release evidence for Microsoft native Windows publisher trust, or automation for human/legal decisions. Do not rewrite historical repository identities where they are part of provenance. Do not retarget immutable tags or replace published release assets in place. A documentation-only commit does not create a new product candidate. Current operational references must resolve to `arvectum2/proxy-launcher`.
