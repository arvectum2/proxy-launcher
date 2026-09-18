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

Current canonical main verified for this roadmap refresh: 52fc4f8bbaa9d7fca6274f28c99041eabf1e410a.
## 2. Russian-first release trust and Windows public trust

- **DONE** — APL-REL-010 real Rutoken/CryptoPro detached-signature POC and the Russian release-evidence architecture.
- **DONE / HISTORICAL EVIDENCE** — the company УКЭП/CryptoPro path is treated as RELEASE-EVIDENCE-ONLY; it is not represented as Microsoft Authenticode/SmartScreen publisher trust.
- **DONE** — APL-REL-011/012/013 release manifest, verification UX and fail-closed Russian production release gate.
- **CURRENT PUBLIC RELEASE** — v0.2.9 is published, but APL-REL-016 remains the separate future native Windows trust track.
- **READY / REVIEW — issue #30, PR #81** — refresh the Windows public-trust decision packet from its v0.2.6 baseline to current v0.2.9; keep SmartScreen/App Reputation, Smart App Control/Application Control, enterprise managed trust and Russian detached evidence separate.
- **OWNER GATE** — provider/certificate selection, spend, key custody and production signing path are not delegated to automation.
- **RULE** — never retrofit embedded signing into an immutable published release; any future Authenticode/public-trust change belongs to a new version.
## 3. IP / legal / sovereignty

- **DONE** — APL-IP-002 platform sovereignty audits.
- **DONE** — APL-IP-003 canonical source refactor, Slices 1–23.
- **DONE** — APL-IP-004 promoted-artifact third-party license bundle engineering.
- **[Web] DONE — post-APL-IP-004 review reconciliation** — historical governance anchor remains candidate `ef9846e151a2e4e7046169e0787603969018cc97`; later technical evidence may bind newer maintained candidates without rewriting this review anchor.
- **APL-IP-001 status: CONDITIONAL / POST-APL-IP-004 ENGINEERING RECONCILED / HUMAN-LEGAL PENDING.**
- **DONE / CURRENT EXACT-OBJECT ENGINEERING** — APL-IP-001 has now been rebound to the exact accepted `v0.2.5` source/tag/artifact identity. Provenance and CycloneDX SBOM evidence are governed for that exact object; issue #57 remains open for final human/legal disposition.
- **PRIVATE RIGHTS EVIDENCE RECORDED** — repository metadata now records SHA-256 digests and the human factual effect of an executed private rights instrument dated 2026-09-14 without publishing the private PDF/signature container. The record also states that the program is not yet registered with Rospatent and that Rospatent is not relied upon as the transfer basis.
- **HUMAN/LEGAL PENDING / NOT APPROVED** — the canonical sign-off record remains fail-closed. R-1/R-2/R-3/R-4 must be actually reviewed and explicitly approved by an authorized human before any clean-IP baseline/tag is created.
- **[Web after explicit APPROVED] — create governed clean-IP baseline/tag** only for the exact candidate authorized by the completed human/legal sign-off.
- **RULE** — automation, repository migration and technical provenance evidence do not substitute for a human/legal decision.
- **HOLD** — AppImage remains outside promoted commercial scope until its downstream/type-2-runtime obligations are separately cleared.

Canonical current records include `docs/APL_IP_001_V0_2_5_SIGNOFF.md` and `docs/evidence/APL_IP_001_V0_2_5_PRIVATE_RIGHTS_EVIDENCE_RECEIPT_2026-09-14.md`.

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

### Android — APL-MOB-001

- **ACTIVE / DRAFT PR #53** — native Android VpnService/TUN dogfood slice exists with simple Russian UX, SOCKS5/HTTP profiles, secure password storage and a CI-built debug APK.
- **READY FOR HUMAN PHYSICAL DOGFOOD** — install on a real Android phone; verify real SOCKS5 and desktop HTTP proxy routing, wrong credentials/outage, browser + ordinary apps, sleep/wake, Wi-Fi↔cellular transitions, performance and credential leakage.
- **POLICY** — the PR remains draft and Always-on/reconnect semantics remain undecided until physical evidence exists.
- **AFTER DOGFOOD** — merge/polish Android MVP, then consider APL-MOB-002 proxy pool/health/failover.

### iOS

- **DEFERRED** — start after Android dogfood establishes stable mobile semantics and the required Apple entitlement/distribution path is clear.
- **CAPABILITY-DEPENDENT** — per-app routing is promised only where platform APIs and distribution model actually allow it.
## 9. Currently available workstreams

1. **[Android / HUMAN] APL-MOB-001 physical dogfood — READY NOW.** PR #53 is technically prepared; the remaining gate is a real phone.
2. **[IP/legal / OWNER] APL-IP-001 final rights/corporate disposition — BLOCKED ON HUMAN EVIDENCE.** Engineering provenance is available; legal/factual approval must be real.
3. **[Windows trust / REVIEW] APL-REL-016 — READY NOW.** PR #81 must be refreshed from v0.2.6 to v0.2.9, then presented for Owner decision.
4. **[Registry infrastructure / HUMAN] APL-REG-001B — BLOCKED UNTIL PHYSICAL RUSSIAN LIFECYCLE EVIDENCE EXISTS.**
5. **[Per-app routing / OWNER] production architecture decision — READY NOW.** PR #68 contains the decision packet; refresh against v0.2.9 if needed, then resolve the Owner stop-gate.
6. **[Registry filing / HUMAN] APL-REG-001E/F — PRE-SUBMISSION HOLD.** Repository dossier is done; private/corporate/accounting/infrastructure/support/signature/live-portal evidence remains.
7. **[Windows/release maintenance] — AVAILABLE AS NEEDED.** PR #80 is a release-evidence workflow maintenance fix and must be reconciled with current main before use.
8. **[macOS production distribution] — DEFERRED.** Engineering baseline exists; Apple production signing/notarization remains non-primary.
9. **[iOS + APL-MOB-002] — DEFERRED.** Starts after Android dogfood.

### Repository-hygiene note

Open PRs #90/#91/#92 are superseded Windows recovery implementations overtaken by merged PR #93/#94 and public v0.2.9. Open PRs #70/#74/#82 are superseded RED OS preparation paths overtaken by merged PR #83. They are not active roadmap tracks and must be reconciled before any reuse.

### Execution order

- Human/device work can advance Android dogfood and the registry/IP evidence gates.
- The hourly watchdog may autonomously advance safe preparation on the earliest independent eligible REVIEW/AUTO workstream; with current HUMAN/OWNER blockers, APL-REL-016 is the first useful review-preparation lane.
- Per-app routing remains an Owner stop-gate after its decision packet is current.
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
| Android | **ACTIVE DOGFOOD / DRAFT PR #53** | Physical phone acceptance |
| iOS | **DEFERRED** | Start after Android dogfood / entitlement path |
## Completion discipline

Do not substitute CI for physical App Control/Astra/РЕД ОС/mobile-device evidence, detached Russian release evidence for Microsoft native Windows publisher trust, or automation for human/legal decisions. Do not rewrite historical repository identities where they are part of provenance. Do not retarget immutable tags or replace published release assets in place. A documentation-only commit does not create a new product candidate. Current operational references must resolve to `arvectum2/proxy-launcher`.
