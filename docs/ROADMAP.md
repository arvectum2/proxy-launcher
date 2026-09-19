# Arvectum Proxy Launcher — canonical roadmap

Updated: 2026-09-19
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Canonical branch: `main`  
Current stable product line: 0.2.10 — public release for Windows x64, Astra Linux 1.8 x86-64, RED OS 8.0.3 x86-64 and generic Linux x86-64 AppImage

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

- **CURRENT / PUBLISHED — v0.2.10** (published 2026-09-19): Windows x64 Setup + portable ZIP, Astra Linux x86-64 DEB, RED OS 8.0.3 x86-64 RPM, generic Linux x86-64 AppImage, plus SHA256SUMS.txt.
- **DONE — AppImage promoted.** PR #111 promoted the governed APL-LNX-008 AppImage engineering lane into the canonical release set; v0.2.10 is the first public stable release that includes the AppImage.
- **CURRENT SAFETY CONTRACT** — Windows rollback/recovery uses the same saved-or-Arvectum ownership rule enforced on Astra/Fly and RED OS/KDE: a third/foreign proxy state fails closed and durable rollback evidence is preserved instead of being overwritten.
- **DONE / PHYSICAL** — Astra Linux Gate R8 is closed on a real Astra Linux SE 1.8/Fly host.
- **DONE / PHYSICAL** — RED OS 8.0.3 Standard Desktop real-host acceptance is closed by PR #83; focused RED OS regression suite 62/62 PASS.
- **DONE / MAC TEST DISTRIBUTION** — separate prerelease v0.2.10-macos-test.1 exists for arm64 dogfood; it is not the stable public macOS lane and does not imply Developer ID/notarization.
- **HISTORICAL** — v0.2.5 remains the first physically sealed Windows CFA-safe baseline and immutable provenance anchor; later releases do not rewrite that evidence.
- **HISTORICAL** — v0.2.6 introduced Windows + Astra, v0.2.7 RED OS, v0.2.8 Linux recovery hardening, v0.2.9 Windows recovery symmetry, and v0.2.10 added the promoted AppImage plus the current desktop packaging baseline.

Current canonical main verified for this roadmap refresh: eff09f7ee25e26991909dedc0918109a7b90a609.
## 2. Russian-first release trust and Windows public trust

- **DONE** — APL-REL-010 real Rutoken/CryptoPro detached-signature POC and the Russian release-evidence architecture.
- **DONE / HISTORICAL EVIDENCE** — the company УКЭП/CryptoPro path is treated as RELEASE-EVIDENCE-ONLY; it is not represented as Microsoft Authenticode/SmartScreen publisher trust.
- **DONE** — APL-REL-011/012/013 release manifest, verification UX and fail-closed Russian production release gate.
- **CURRENT PUBLIC RELEASE** — v0.2.10 is published without native Authenticode; APL-REL-016 remains the separate future Windows publisher-trust track.
- **READY FOR OWNER REVIEW — issue #30, PR #132** — current v0.2.10 / first-eligible-v0.2.11+ Windows public-trust packet is prepared and exact-head CI is green. The REVIEW lane stops before merge, provider selection, certificate spend, key custody, production signing or release.
- **OWNER GATE** — provider/certificate selection, spend, key custody and production signing path are not delegated to automation.
- **RULE** — never retrofit embedded signing into an immutable published release; any future Authenticode/public-trust change belongs to a new version.
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
- **DONE / TEST DISTRIBUTION** — separate arm64 prerelease `v0.2.10-macos-test.1` was published for dogfood and mirrored with checksum parity. It is not the stable production macOS channel.
- **DEFERRED** — Apple production identity signing/notarization under the Russia-first priority model.
- **DEFERRED** — controlled endpoint-denied build-input hardening where it requires Apple-specific production infrastructure.
- **OPTIONAL FUTURE** — keep `.app`/DMG as the normal macOS distribution lane; add a separate portable form only if it provides a real operational benefit and does not weaken recovery/update semantics.

## 7. Per-application routing — next desktop product capability

- **DONE** — APL-ROUTE-001 platform-neutral routing-rule model.
- **DONE** — APL-ROUTE-002 per-platform feasibility matrix.
- **AUTONOMOUS COMPLETE / LOCAL-NATIVE PENDING** — APL-ROUTE-003 Windows control-plane prototype.
- **DONE** — APL-ROUTE-004 durable ownership/recovery/security journal.
- **READY FOR OWNER DECISION — PR #68** — the production enforcement decision packet is open. It recommends, without approving, a narrow Arvectum-owned WFP ALE callout + privileged service + local proxy path.
- **STOP-GATE** — architecture selection is reserved to Owner/Product Owner. Automation may refresh the packet against the v0.2.9 safety baseline and prepare reversible prototypes, but must not treat a recommendation as approval.
- **AFTER APPROVAL** — implementation requires real Windows host acceptance, ownership/recovery proofs and a new product version.
## 8. Mobile applications

### Android — APL-MOB-001 / APL-MOB-002 / APL-MOB-003 / APL-MOB-004

- **DONE — APL-MOB-001 Android dogfood baseline.** The physically accepted VpnService/TUN transport baseline supports real HTTP/HTTPS CONNECT traffic, multiprofile storage and the one-button mobile UX.
- **DONE — APL-MOB-002 proxy pool / automatic failover.** Android 0.1.17 is physically accepted and publicly released; Wi-Fi -> hotspot -> Wi-Fi handoff and automatic proxy failover recover without manual OFF/ON.
- **DONE / INTEGRATED — APL-MOB-003 site exclusions.** Android 0.1.19 site exclusions and clarified Add/list/remove UX were physically accepted; original PR #125 was superseded and rebased integration PR #130 merged to `main` as `c645825ec8b3fd142e0b6b7eca3c1fc8f6261550`. No public Android 0.1.19 release is implied by the merge alone.
- **PLANNED / OWNER-GATED — APL-MOB-004 Android monetization + dual distribution.** MOB-003 is complete and integrated. Start implementation only after the Owner explicitly prioritizes monetization and decides the private package/update identity.
  - Public Android artifacts distributed through GitHub, GitVerse, the Arvectum site and RuStore will use the ad-enabled channel after APL-MOB-004 is released.
  - Initial monetization target: Yandex Mobile Ads / App Open advertising, with first-launch grace, frequency limiting, fail-open behavior when an ad is unavailable, and privacy/consent documentation before production enablement.
  - A private no-ads build will be produced from the same product code, not maintained as a divergent second application. Prefer Gradle product flavors/build configuration with the ad SDK absent or disabled in the private artifact.
  - A public GitHub repository cannot contain a private branch or private Release. The no-ads delivery lane therefore requires a separate private remote/repository (or a Mac-only private branch until that remote exists) and a private release artifact.
  - Keep a stable latest private APK on the Mac mini under an Arvectum release directory, in addition to immutable versioned private APKs and hashes.
  - Before implementation, choose private package identity/update semantics explicitly so RuStore/public auto-updates cannot unexpectedly replace the no-ads build with the ad-enabled build.
  - Historical public releases remain immutable; advertising is introduced only by a new Android product version.

### iOS

- **DEFERRED** — start after Android dogfood establishes stable mobile semantics and the required Apple entitlement/distribution path is clear.
- **CAPABILITY-DEPENDENT** — per-app routing is promised only where platform APIs and distribution model actually allow it.
## 9. Currently available workstreams

1. **[Android / OWNER] APL-MOB-001/002/003 — DONE; APL-MOB-004 — PLANNED/OWNER-GATED.** Site exclusions are integrated via PR #130; monetization/dual distribution starts only after explicit Owner priority and package/update-identity decision, and must not start per-application routing.
2. **[IP/legal] APL-IP-001 v0.2.9 filing-evidence packet — DONE.** Optional external legal hardening is non-blocking unless specifically requested.
3. **[Windows trust / REVIEW] APL-REL-016 — READY FOR OWNER REVIEW.** PR #132 is the current v0.2.10 / v0.2.11+ packet with exact-head CI green; it stops before merge/provider/certificate/key-custody decisions.
4. **[Registry infrastructure / HUMAN] APL-REG-001B — BLOCKED UNTIL PHYSICAL RUSSIAN LIFECYCLE EVIDENCE EXISTS.**
5. **[Per-app routing / OWNER] production architecture decision — READY NOW.** PR #68 contains the decision packet; its assumptions may be safely refreshed against v0.2.10, but architecture selection remains an Owner stop-gate.
6. **[Registry filing / HUMAN] APL-REG-001E/F — PRE-SUBMISSION HOLD.** Repository dossier is done; private/accounting/infrastructure/support/signature/live-portal evidence remains.
7. **[Windows/release maintenance] — AVAILABLE AS NEEDED.** PR #80 is a release-evidence workflow maintenance fix and must be reconciled with current main before use.
8. **[macOS production distribution] — DEFERRED.** Engineering baseline exists; Apple production signing/notarization remains non-primary.
9. **[iOS] — DEFERRED.** Start after the Android product semantics are stable and the Apple entitlement/distribution path is explicit.

### Repository-hygiene note

Open PRs #81/#103 are superseded Windows-trust preparation paths; PR #132 is the current REVIEW packet. Original MOB-003 PR #125 is superseded by merged integration PR #130. Open PRs #90/#91/#92 are superseded Windows recovery implementations overtaken by merged PR #93/#94; open PRs #70/#74/#82 are superseded RED OS preparation paths overtaken by merged PR #83. They are not active roadmap tracks and must be reconciled before any reuse.

### Execution order

- APL-MOB-003 is complete/integrated; APL-MOB-004 is waiting on explicit Owner prioritization/package identity, so automation must not start ad-provider implementation by itself.
- APL-REL-016 has reached the Owner-review boundary in PR #132; the watchdog should not recreate the packet or merge it automatically.
- After REL-016 reaches the Owner-review boundary again, the next safe repository-preparation lane is refreshing per-app-routing decision material in PR #68 against v0.2.10; architecture selection itself remains an Owner stop-gate.
- External Ministry submission remains outside automation.
## 10. Platform / distribution matrix

| Platform / form | Current state | Next gate |
| --- | --- | --- |
| Windows installer | **PUBLISHED v0.2.10** | Maintenance; APL-REL-016 for a future signed release |
| Windows portable | **PUBLISHED v0.2.10** | Maintenance / future feature release |
| Astra Linux .deb | **PUBLISHED v0.2.10 / PHYSICAL BASELINE PROVEN** | Existing Astra acceptance retained; rerun only when required by a material change/filing gate |
| RED OS .rpm | **PUBLISHED v0.2.10 / PHYSICAL BASELINE PROVEN** | Existing RED OS acceptance retained; rerun only when required by a material change/filing gate |
| Linux AppImage | **PUBLISHED v0.2.10** | Maintain governed runtime/license/release parity |
| macOS .app / DMG | **TEST PRERELEASE v0.2.10-macos-test.1 / PRODUCTION DEFERRED** | Apple Developer ID signing/notarization when prioritized |
| Android | **0.1.17 PUBLIC / APL-MOB-003 0.1.19 DONE+MERGED / APL-MOB-004 PLANNED** | Owner prioritization/package identity for ads-enabled public + private no-ads distribution; public 0.1.19 release is separate |
| iOS | **DEFERRED** | Start after Android product semantics / entitlement path |

## Completion discipline

Do not substitute CI for physical App Control/Astra/РЕД ОС/mobile-device evidence, detached Russian release evidence for Microsoft native Windows publisher trust, or automation for human/legal decisions. Do not rewrite historical repository identities where they are part of provenance. Do not retarget immutable tags or replace published release assets in place. A documentation-only commit does not create a new product candidate. Current operational references must resolve to `arvectum2/proxy-launcher`.
