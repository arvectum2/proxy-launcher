# Arvectum Proxy Launcher — canonical roadmap

Updated: 2026-09-13  
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Canonical branch: `main`  
Current stable product line: `0.2.5` — Windows stable release published on GitHub and independently mirrored to GitVerse

Status legend: **DONE**, **PUBLISHED**, **CURRENT**, **READY NOW**, **READY**, **IMPLEMENTED**, **PARTIAL**, **HUMAN/LEGAL PENDING**, **STOP-GATE**, **DEFERRED**, **FUTURE**.

## 0. Repository authority and release baseline

- **DONE** — source/history/tags were recovered into `arvectum2/proxy-launcher`; `main` is the canonical integration branch.
- **DONE** — current governance, installer/support and repository-identity references are normalized to the canonical slug without rewriting historical provenance.
- **DONE** — GitVerse mirror logic is owner-independent on the GitHub side and current GitHub/GitVerse release mirroring is operational.
- **DONE** — exact-SHA GitHub Actions evidence was rebuilt in the canonical repository for Windows portable, Windows installer/Gate R6, SAST, SBOM, provenance and release evidence.
- **DONE** — `main` protection is governed by the active `Protect main` ruleset; PR + required `build` enforcement and negative merge acceptance have been proven.
- **MIGRATION CLOSED** — the `arvectum1 -> arvectum2` repository migration is no longer an active project gate.

Historical repository identifiers remain valid only inside explicit provenance, closed acceptance, immutable baseline or historical workflow material. They are not current operational authorities.

## 1. Windows stable product line

- **DONE** — customer-proven Windows `0.2.3` system-proxy baseline.
- **DONE / HISTORICAL INTERMEDIATE** — `0.2.4` physical/release-hardening candidate and APL-WIN-014 App Control work. Its evidence remains provenance, but `0.2.4` is no longer the current product line.
- **DONE / PHYSICAL PASS** — `0.2.5` CFA-safe installer/runtime hotfix physically accepted on the owner-operated Windows host with Controlled Folder Access enabled.
- **DONE / PHYSICAL PASS** — clean reboot proved canonical autostart, exactly one runtime on `127.0.0.1:8082`, PAC HTTP `200`, real HTTPS traffic through the local proxy, and absence of the legacy Python runtime.
- **SEALED IDENTITY** — accepted product source: `9e8ca7e851563082cd7d03d7543ccb360a37ec27`; accepted Setup SHA-256: `9b5368d67874b7164ee56a245c75db4b23af593a1d72f7e947774516abcc95e3`; accepted installed application SHA-256: `1ab36b7a6a0a225dcf06fb2c630d0d2ba47ec17578dbd5949f08e992853d653c`.
- **PUBLISHED** — GitHub stable release `v0.2.5` is public and immutable under Arvectum release policy. Do not move the tag or replace assets in place.
- **PUBLISHED** — Windows installer and portable release are both distributed as governed `0.2.5` assets.

Canonical closure records:

- `docs/evidence/APL_0_2_5_CFA_PHYSICAL_ACCEPTANCE_2026-09-13.md`
- `docs/evidence/APL_0_2_5_FINAL_PHYSICAL_REBOOT_2026-09-13.json`
- `docs/releases/0.2.5.md`

## 2. Russian-first release trust and distribution

- **DONE** — APL-REL-010 real Rutoken/CryptoPro POC: detached signing and verification PASS.
- **DONE** — current company УКЭП is intentionally classified `RELEASE-EVIDENCE-ONLY`; it is not represented as Microsoft Authenticode trust.
- **DONE** — APL-REL-011 owner-operated signed-release manifest integration.
- **DONE** — APL-REL-012 end-user verification UX.
- **DONE** — APL-REL-013 fail-closed Russian production release gate.
- **DONE / HISTORICAL** — APL-REL-014 `0.2.4` exact signed-set/lifecycle work is retained as release-hardening provenance rather than a current blocker.
- **DONE / PUBLISHED** — APL-REL-015 binds the physically accepted `0.2.5` CFA hotfix identity into the exact Russian release-evidence/publication path.
- **PUBLISHED** — `v0.2.5` public set is bound by SHA-256 and detached CryptoPro/Rutoken signature/certificate evidence.
- **PUBLISHED / MIRRORED** — GitVerse is an independent Russian distribution point for `v0.2.5`. The canonical release has 9 public payloads; unsupported GitVerse extensions are carried in lossless one-file ZIP wrappers and verified back against canonical SHA-256 values. See `docs/releases/0.2.5-gitverse-mirror.md`.
- **READY NOW / OPEN ISSUE #30** — APL-REL-016: define the Windows public-trust strategy for future releases (`0.2.6+`): distinguish SmartScreen/App Reputation, Smart App Control/Application Control, managed enterprise trust and Russian detached evidence; investigate Russian-native options first. International Microsoft/OV/EV provider paths remain low priority unless required by the chosen native Windows trust model.
- **RULE** — REL-016 must not mutate `v0.2.5`; any embedded PE/Authenticode change belongs to a new release.

## 3. IP / legal / sovereignty

- **DONE** — APL-IP-002 platform sovereignty audits.
- **DONE** — APL-IP-003 canonical source refactor, Slices 1–23.
- **DONE** — APL-IP-004 promoted-artifact third-party license bundle engineering.
- **[Web] DONE — post-APL-IP-004 review reconciliation** — historical governance anchor remains candidate `ef9846e151a2e4e7046169e0787603969018cc97`; later technical evidence may bind newer maintained candidates without rewriting this review anchor.
- **APL-IP-001 status: CONDITIONAL / POST-APL-IP-004 ENGINEERING RECONCILED / HUMAN-LEGAL PENDING.**
- **HUMAN/LEGAL PENDING** — close the remaining APL-IP-001 factual/legal boundary: R-1 author -> ООО rights basis; R-2 actual Rospatent status; R-3 corporate/interested-transaction basis where applicable; factual confirmation; explicit authorized final decision.
- **[Web after explicit APPROVED] — create governed clean-IP baseline/tag** only for the exact candidate authorized by the completed human/legal sign-off.
- **RULE** — automation, repository migration and technical provenance evidence do not substitute for a human/legal decision.
- **HOLD** — AppImage remains outside promoted commercial scope until its downstream/type-2-runtime obligations are separately cleared.

The human/legal clean-IP lane remains important corporate/IP work, but it is no longer described as an unperformed `0.2.5` publication step: `v0.2.5` has already been published. The clean-IP decision governs its own controlled baseline/tag and future legal package.

## 4. Linux / Astra Linux — next platform lane

- **DONE** — APL-LNX-001..009 engineering: environment detection, NetworkManager preflight, capability UX, PolicyKit UX, autostart, diagnostics, Debian package, AppImage engineering and Ubuntu CI acceptance.
- **READY NOW / RECOMMENDED NEXT** — convert `ARVECTUM-DEMO` to persistent Windows 11 + Astra Linux SE 1.8 dual boot. The Windows `0.2.5` release/evidence set is now externally preserved and published, so the old Windows-release-preservation dependency is closed.
- **READY NOW** — APL-LNX-010 real Astra acceptance on physical Astra Linux.
- **PENDING** — Gate R8 closes only from real Astra-host PASS evidence; Ubuntu CI is not a substitute.
- **PROMOTED LANE** — Debian `.deb` remains the preferred Linux/Astra production package.
- **HOLD FOR COMMERCIAL PROMOTION** — AppImage can remain an engineering/portable option, but does not enter the promoted commercial set until its compliance obligations are separately cleared.

APL-LNX-010 acceptance should cover at minimum: install/update/remove, GUI/runtime startup, NetworkManager/PolicyKit behavior, enable/sync/disable, rollback, autostart, crash/reboot recovery, diagnostics/privacy and preservation of Windows dual-boot bootability.

## 5. macOS

- **DONE** — APL-MAC-001..008 engineering/acceptance track and Gate R9 evidence retained.
- **DEFERRED** — Apple production identity signing/notarization under the Russia-first priority model.
- **DEFERRED** — controlled endpoint-denied build-input hardening where it requires Apple-specific production infrastructure.
- **OPTIONAL FUTURE** — keep `.app`/DMG as the normal macOS distribution lane; add a separate portable form only if it provides a real operational benefit and does not weaken recovery/update semantics.

## 6. Per-application routing — next product capability

- **DONE** — APL-ROUTE-001 platform-neutral routing-rule model.
- **DONE** — APL-ROUTE-002 per-platform feasibility matrix.
- **AUTONOMOUS COMPLETE / LOCAL-NATIVE PENDING** — APL-ROUTE-003 Windows control-plane prototype.
- **DONE** — APL-ROUTE-004 durable ownership/recovery/security journal.
- **READY NOW FOR ARCHITECTURE DECISION** — the prerequisite “stable Windows baseline proven in the field/physically” is now satisfied by the `0.2.5` line.
- **STOP-GATE** — before Windows native production enforcement, deliberately choose an accepted enforcement architecture. Test-signing/developer modes are not a production workaround.
- **AFTER WINDOWS NATIVE PATH** — extend the same product model to macOS/Linux where technically appropriate, with capability-aware UX rather than pretending every platform supports identical enforcement.

Per-application routing must remain a new-version feature. It must not be retrofitted into immutable `v0.2.5` assets.

## 7. Mobile applications — future platform stage

- **FUTURE / AFTER DESKTOP BASELINES** — build iOS and Android applications as the next platform stage after the desktop product lines are sufficiently stable.
- **FUTURE** — carry over the common routing/configuration model where platform APIs permit it.
- **FUTURE / CAPABILITY-DEPENDENT** — support application-level selection/routing on iOS/Android only to the extent allowed by each platform; unsupported capabilities must be explicit in UX rather than emulated unsafely.

Mobile work is not a blocker for Windows/Astra/macOS release closure.

## 8. All currently available next steps

The project no longer has a single mandatory sequential next step. The following lanes are available from the current `0.2.5` baseline:

1. **[Linux / recommended primary] APL-LNX-010 real Astra acceptance — READY NOW.** Prepare the dual-boot stand, install Astra Linux SE 1.8, test the `.deb` end-to-end and close Gate R8 from physical evidence.
2. **[Windows trust / parallel] APL-REL-016 — READY NOW.** Investigate and choose the future Windows public-trust/distribution model without mutating `v0.2.5`; target any binary-signing change at `0.2.6+`.
3. **[Human/legal / parallel] APL-IP-001 final sign-off — READY FOR HUMAN INPUT.** Close R-1/R-2/R-3, factual provenance and the authorized clean-IP decision; if `APPROVED`, create the governed clean-IP baseline/tag.
4. **[Product / parallel discovery] per-application routing architecture — READY NOW.** Resolve the Windows enforcement STOP-GATE and define the first production-native increment after the existing control-plane prototype.
5. **[macOS / optional priority] production distribution hardening — AVAILABLE BUT DEFERRED.** Apple signing/notarization and production distribution can be activated when macOS becomes a commercial priority.
6. **[Windows maintenance] `0.2.5` support/hotfix lane — AVAILABLE AS NEEDED.** Triage field feedback and regressions; any changed product bytes require a new version and fresh exact-byte evidence rather than replacing `v0.2.5`.
7. **[Release] next SemVer release — AVAILABLE WHEN A MATERIAL CHANGE EXISTS.** Do not create `0.2.6` merely to refresh documentation; use it for REL-016 signing/distribution changes, bug fixes, routing increments or another real product change, then repeat the applicable exact-SHA/physical/release-evidence gates.
8. **[Mobile] iOS/Android — PLANNED, NOT YET PRIMARY.** Start after desktop baselines are sufficiently mature; preserve capability-aware routing semantics.

### Recommended execution order from 2026-09-13

1. **APL-LNX-010 / Astra Linux real-host acceptance and Gate R8.**
2. In parallel, **APL-REL-016 Russian-first Windows trust investigation** and **APL-IP-001 human/legal closure**.
3. After Gate R8, choose whether the next product increment is **Windows per-application routing** or **macOS production distribution**, based on commercial demand.
4. Cut the next SemVer release only when one of those material changes is ready for governed acceptance.
5. Move to **iOS/Android** after the desktop matrix is sufficiently stable.

## 9. Desktop release matrix

| Platform / form | Current state | Next gate |
| --- | --- | --- |
| Windows installer | **PUBLISHED 0.2.5** | REL-016 only for future native Windows trust; otherwise maintenance |
| Windows portable | **PUBLISHED 0.2.5** | Maintenance / future feature release |
| Linux Debian `.deb` | **ENGINEERING DONE** | APL-LNX-010 physical Astra PASS / Gate R8 |
| Linux AppImage | **ENGINEERING DONE / COMMERCIAL HOLD** | Separate compliance clearance before promotion |
| macOS `.app` / DMG | **ENGINEERING/ACCEPTANCE DONE** | Apple production signing/notarization when prioritized |
| macOS portable | **OPTIONAL FUTURE** | Implement only if technically/product-wise useful |
| iOS | **FUTURE** | Mobile-stage architecture |
| Android | **FUTURE** | Mobile-stage architecture |

## Completion discipline

Do not substitute CI for physical App Control/Astra evidence, detached Russian release evidence for Microsoft native Windows publisher trust, or automation for human/legal decisions. Do not rewrite historical repository identities where they are part of provenance. Do not retarget immutable tags or replace published release assets in place. A documentation-only commit does not create a new product candidate. Current operational references must resolve to `arvectum2/proxy-launcher`.
