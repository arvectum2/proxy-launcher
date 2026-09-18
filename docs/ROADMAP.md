# Arvectum Proxy Launcher — canonical roadmap

Updated: 2026-09-18
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Canonical branch: `main`  
Current stable product line: 0.2.9 — stable rollback-safety release for Windows x64, Astra Linux 1.8 x86-64 and RED OS 8.0.3 x86-64

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

- **CURRENT / PUBLISHED — v0.2.9** (published 2026-09-17): Windows x64 Setup + portable ZIP, Astra Linux x86-64 DEB, RED OS 8.0.3 x86-64 RPM, plus SHA256SUMS.txt.
- **CURRENT SAFETY CONTRACT** — Windows rollback/recovery now uses the same saved-or-Arvectum ownership rule already enforced on Astra/Fly and RED OS/KDE: a third/foreign proxy state fails closed and durable rollback evidence is preserved instead of being overwritten.
- **DONE** — the Windows ownership-symmetry fix was merged through PR #93 and closed out by PR #94 before the public v0.2.9 release.
- **DONE / PHYSICAL** — Astra Linux Gate R8 is closed on a real Astra Linux SE 1.8/Fly host.
- **DONE / PHYSICAL** — RED OS 8.0.3 Standard Desktop real-host acceptance is closed by PR #83; focused RED OS regression suite 62/62 PASS.
- **HISTORICAL** — v0.2.5 remains the first physically sealed Windows CFA-safe baseline and immutable provenance anchor; later releases do not rewrite that evidence.
- **HISTORICAL** — v0.2.6 introduced the first Windows + Astra release lane; v0.2.7 added the RED OS release track; v0.2.8 hardened Linux mixed-state recovery; v0.2.9 closes the Windows recovery-symmetry gap.

Current canonical main verified for this roadmap refresh: 2cb0921c1fe31a22f1ea054fb4d37af2e5fca021.
## 2. Russian-first release trust and Windows public trust

- **DONE** — APL-REL-010 real Rutoken/CryptoPro detached-signature POC and the Russian release-evidence architecture.
- **DONE / HISTORICAL EVIDENCE** — the company УКЭП/CryptoPro path is treated as RELEASE-EVIDENCE-ONLY; it is not represented as Microsoft Authenticode/SmartScreen publisher trust.
- **DONE** — APL-REL-011/012/013 release manifest, verification UX and fail-closed Russian production release gate.
- **CURRENT PUBLIC RELEASE** — v0.2.9 is published, but APL-REL-016 remains the separate future native Windows trust track.
- **READY FOR OWNER REVIEW — issue #30, PR #103** — the Windows public-trust packet has been refreshed to immutable v0.2.9; PR #103 supersedes stale PR #81 and defines 0.2.10+ as the first eligible embedded-signing/public-trust release. Focused public-trust and release/repository suites recorded by the PR pass; final decision/merge remains reserved.
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
- **CURRENT SCOPE** — Windows Setup + portable, Astra DEB and RED OS RPM. AppImage is excluded from the current approval only and may be added later through its own release/compliance gate.
- **PROCESS CORRECTION** — the previously prepared R-1B two-party/self-signing future-rights agreement is not a mandatory APL-IP-001 or registry-filing step. It is retained only as optional external legal hardening for the residual question of later human-authored copyrightable contributions. Do not reintroduce it as a blocker without new Owner/legal input.
- **RULE** — repository evidence is not a legal opinion. If the registry/expert or external counsel specifically requests a stronger chain-of-title instrument for later contributions, handle that as a targeted legal-hardening task rather than per-version compliance ritual.

Canonical current records: `docs/APL_IP_001_V0_2_9_SIGNOFF.md`, `docs/evidence/APL_IP_001_V0_2_9_CANDIDATE_RECONCILIATION_2026-09-18.md`, `docs/evidence/APL_IP_001_V0_2_9_OWNER_FACT_CONFIRMATION_2026-09-18.md`. Historical v0.2.5 records remain evidence.

## 4. Linux / Astra Linux

- **DONE** — APL-LNX-001..009 engineering: environment detection, NetworkManager preflight, capability/PolicyKit UX, autostart, diagnostics, Debian packaging and CI acceptance.
- **DONE / PHYSICAL PASS** — APL-LNX-010 / Gate R8 on Astra Linux Special Edition 1.8/Fly. Real-host evidence covers install, GUI/runtime, NetworkManager enable/disable, exact rollback, crash/reboot recovery, autostart, package lifecycle, diagnostics/privacy and cleanup.
- **DONE** — APL-LNX-011 fixed Firefox system-proxy behavior on Astra/Fly and was closed by PR #71/#72.
- **CURRENT RELEASE** — v0.2.9 publishes Arvectum-Proxy-Launcher-0.2.9-astra-linux-amd64.deb.
- **PROMOTED LANE** — Debian .deb remains the preferred Astra/Linux package.
- **HOLD** — AppImage remains outside the promoted commercial set until its separate downstream/type-2-runtime compliance obligations are cleared.
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

### Android — APL-MOB-001 / APL-MOB-002

- **DONE — APL-MOB-001 Android dogfood baseline.** PR #53 merged the physically accepted 0.1.4 VpnService/TUN transport baseline with real HTTP/HTTPS CONNECT traffic, public-IP change and lifecycle checks.
- **DONE — multiprofile MVP increment.** PR #104 merged 0.1.5 multiprofile migration/save/select/delete after its physical upgrade and two-profile selection gate.
- **IN PROGRESS / DRAFT PR #105 — APL-MOB-002.** Manual connected A → B hot switch and pool-level Auto selection/networking are already recorded as physically accepted. The current 0.1.7 candidate adds a dedicated Auto screen, Arvectum branding, large circular power control and adaptive launcher icon.
- **CURRENT HUMAN GATE** — install 0.1.7 over the accepted prior build and verify Auto/editor separation, branded rendering/press feedback, unclipped launcher icon and unchanged hot-switch/network behavior.
- **LATER APL-MOB-002 SLICE** — continuous background failover after an already-connected upstream dies; do not conflate this with the already accepted manual hot-switch/initial Auto selection behavior.

### iOS

- **DEFERRED** — start after Android dogfood establishes stable mobile semantics and the required Apple entitlement/distribution path is clear.
- **CAPABILITY-DEPENDENT** — per-app routing is promised only where platform APIs and distribution model actually allow it.
## 9. Currently available workstreams

1. **[Android / HUMAN] APL-MOB-001 Android baseline — DONE; APL-MOB-002 PR #105 — IN PROGRESS.** Current gate is the 0.1.7 physical UX/branding/network-regression check; continuous background failover is a later slice.
2. **[IP/legal] APL-IP-001 v0.2.9 filing-evidence packet — DONE.** Optional external legal hardening is non-blocking unless specifically requested.
3. **[Windows trust / REVIEW] APL-REL-016 — READY FOR OWNER REVIEW.** PR #103 is the current v0.2.9 packet; PR #81 is superseded. No provider, certificate, key-custody or release action is approved by the packet itself.
4. **[Registry infrastructure / HUMAN] APL-REG-001B — BLOCKED UNTIL PHYSICAL RUSSIAN LIFECYCLE EVIDENCE EXISTS.**
5. **[Per-app routing / OWNER] production architecture decision — READY NOW.** PR #68 contains the decision packet; its assumptions may be safely refreshed against v0.2.9, but architecture selection remains an Owner stop-gate.
6. **[Registry filing / HUMAN] APL-REG-001E/F — PRE-SUBMISSION HOLD.** Repository dossier is done; private/accounting/infrastructure/support/signature/live-portal evidence remains.
7. **[Windows/release maintenance] — AVAILABLE AS NEEDED.** PR #80 is a release-evidence workflow maintenance fix and must be reconciled with current main before use.
8. **[macOS production distribution] — DEFERRED.** Engineering baseline exists; Apple production signing/notarization remains non-primary.
9. **[iOS] — DEFERRED.** Start after the Android product semantics are stable and the Apple entitlement/distribution path is explicit.

### Repository-hygiene note

Open PR #81 is superseded by current APL-REL-016 PR #103. Open PRs #90/#91/#92 are superseded Windows recovery implementations overtaken by merged PR #93/#94 and public v0.2.9. Open PRs #70/#74/#82 are superseded RED OS preparation paths overtaken by merged PR #83. They are not active roadmap tracks and must be reconciled before any reuse.

### Execution order

- Human/device work can advance the current APL-MOB-002 0.1.7 physical gate and the registry physical/private evidence gates.
- APL-REL-016 preparation is already at the Owner-review boundary in PR #103; the watchdog should not repeatedly recreate that work.
- The next safe repository-preparation lane is the v0.2.9 refresh of per-app-routing decision material in PR #68, while architecture selection itself remains an Owner stop-gate.
- External Ministry submission remains outside automation.
## 10. Platform / distribution matrix

| Platform / form | Current state | Next gate |
| --- | --- | --- |
| Windows installer | **PUBLISHED v0.2.9** | Maintenance; APL-REL-016 for future native public trust |
| Windows portable | **PUBLISHED v0.2.9** | Maintenance / future feature release |
| Astra Linux .deb | **PUBLISHED v0.2.9 / PHYSICAL BASELINE PROVEN** | Optional exact-v0.2.9 future-proof smoke for registry evidence |
| RED OS .rpm | **PUBLISHED v0.2.9 / PHYSICAL BASELINE PROVEN** | Optional exact-v0.2.9 future-proof smoke; registry physical acceptance already exists |
| Linux AppImage | **ENGINEERING DONE / COMMERCIAL HOLD** | Separate compliance clearance |
| macOS .app / DMG | **ENGINEERING/ACCEPTANCE DONE** | Apple production signing/notarization when prioritized |
| Android | **APL-MOB-001 BASELINE DONE / APL-MOB-002 DRAFT PR #105** | 0.1.7 physical UX/branding/regression gate; later continuous failover |
| iOS | **DEFERRED** | Start after Android dogfood / entitlement path |
## Completion discipline

Do not substitute CI for physical App Control/Astra/РЕД ОС/mobile-device evidence, detached Russian release evidence for Microsoft native Windows publisher trust, or automation for human/legal decisions. Do not rewrite historical repository identities where they are part of provenance. Do not retarget immutable tags or replace published release assets in place. A documentation-only commit does not create a new product candidate. Current operational references must resolve to `arvectum2/proxy-launcher`.
