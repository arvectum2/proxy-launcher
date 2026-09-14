# Arvectum Proxy Launcher — canonical roadmap

Updated: 2026-09-14  
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Canonical branch: `main`  
Current stable product line: `0.2.5` — Windows stable release published on GitHub and independently mirrored to GitVerse

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
- **DONE / CURRENT EXACT-OBJECT ENGINEERING** — APL-IP-001 has now been rebound to the exact accepted `v0.2.5` source/tag/artifact identity. Provenance and CycloneDX SBOM evidence are governed for that exact object; issue #57 remains open for final human/legal disposition.
- **PRIVATE RIGHTS EVIDENCE RECORDED** — repository metadata now records SHA-256 digests and the human factual effect of an executed private rights instrument dated 2026-09-14 without publishing the private PDF/signature container. The record also states that the program is not yet registered with Rospatent and that Rospatent is not relied upon as the transfer basis.
- **HUMAN/LEGAL PENDING / NOT APPROVED** — the canonical sign-off record remains fail-closed. R-1/R-2/R-3/R-4 must be actually reviewed and explicitly approved by an authorized human before any clean-IP baseline/tag is created.
- **[Web after explicit APPROVED] — create governed clean-IP baseline/tag** only for the exact candidate authorized by the completed human/legal sign-off.
- **RULE** — automation, repository migration and technical provenance evidence do not substitute for a human/legal decision.
- **HOLD** — AppImage remains outside promoted commercial scope until its downstream/type-2-runtime obligations are separately cleared.

Canonical current records include `docs/APL_IP_001_V0_2_5_SIGNOFF.md` and `docs/evidence/APL_IP_001_V0_2_5_PRIVATE_RIGHTS_EVIDENCE_RECEIPT_2026-09-14.md`.

## 4. Linux / Astra Linux — primary desktop platform lane

- **DONE** — APL-LNX-001..009 engineering: environment detection, NetworkManager preflight, capability UX, PolicyKit UX, autostart, diagnostics, Debian package, AppImage engineering and Ubuntu CI acceptance.
- **READY NOW / RECOMMENDED PRIMARY LOCAL TASK** — convert `ARVECTUM-DEMO` to persistent Windows 11 + Astra Linux SE 1.8 dual boot. The Windows `0.2.5` release/evidence set is externally preserved and published, so the old Windows-release-preservation dependency is closed.
- **READY NOW** — APL-LNX-010 real Astra acceptance on physical Astra Linux.
- **PENDING** — Gate R8 closes only from real Astra-host PASS evidence; Ubuntu CI is not a substitute.
- **PROMOTED LANE** — Debian `.deb` remains the preferred Linux/Astra production package.
- **HOLD FOR COMMERCIAL PROMOTION** — AppImage can remain an engineering/portable option, but does not enter the promoted commercial set until its compliance obligations are separately cleared.

APL-LNX-010 acceptance should cover at minimum: install/update/remove, GUI/runtime startup, NetworkManager/PolicyKit behavior, enable/sync/disable, rollback, autostart, crash/reboot recovery, diagnostics/privacy and preservation of Windows dual-boot bootability.

## 5. Russian Software Register / APL-REG-001

This is now a distinct active workstream rather than an implicit legal tail of Linux/IP work.

- **DECIDED** — APL-REG-001A classification working position: primary class `02.02 — Программы обслуживания`, with mandatory final classifier/law recheck immediately before filing.
- **DONE** — APL-IP-002 sovereignty inventory feeds this workstream.
- **REPOSITORY TOOLING COMPLETE / PHYSICAL GATE OPEN** — APL-REG-001B sovereign lifecycle contract/tooling exists. Remaining proof must come from real Russian-controlled source/build/artifact/distribution infrastructure; GitHub/GitHub Actions/GitHub Releases remain development/secondary channels, not filing-grade proof by themselves.
- **ASTRA RECORD DONE / RED OS PHYSICAL GATE OPEN** — APL-REG-001C now has the completed Astra Linux SE record. RED OS RPM packaging and strict acceptance tooling are prepared in draft PR #70; the remaining second-OS gate is the real RED OS run.
- **WORKING ACCEPTANCE PAIR** — Astra Linux Special Edition + РЕД ОС, subject to re-verification of qualifying status and different-rightsholder status at execution time.
- **RESUME GATE** — do not continue compatibility-dependent registry engineering/documentation until both real-host acceptance runs exist. Generic Ubuntu CI, containers or claimed Python portability do not substitute.
- **AFTER TWO-OS PASS** — reconcile platform differences/failures, implement only required compatibility changes, rerun affected cases, freeze compatibility contract, then produce expert-readable protocols.
- **THEN** — APL-REG-001D registry documentation pack; APL-REG-001E private corporate evidence pack; APL-REG-001F pre-submission audit.

Canonical registry readiness contract: `APL-REG-001_RUSSIAN_SOFTWARE_REGISTRY_READINESS.md`.

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
- **READY NOW FOR ARCHITECTURE DECISION** — the prerequisite “stable Windows baseline proven in the field/physically” is satisfied by the `0.2.5` line.
- **STOP-GATE** — before Windows native production enforcement, deliberately choose an accepted enforcement architecture. Test-signing/developer modes are not a production workaround.
- **AFTER WINDOWS NATIVE PATH** — extend the same product model to macOS/Linux where technically appropriate, with capability-aware UX rather than pretending every platform supports identical enforcement.

Per-application routing must remain a new-version feature. It must not be retrofitted into immutable `v0.2.5` assets.

## 8. Mobile applications

### Android — APL-MOB-001 active dogfood branch

- **ACTIVE / DRAFT PR #53** — `apl-mob-001-android-spike` now contains a native Android project and real `VpnService`/TUN dogfood slice; this is no longer merely a future idea.
- **IMPLEMENTED IN SPIKE** — minimal Russian UX, SOCKS5/HTTP proxy profile, full-device IPv4/IPv6 routing, virtual DNS, self-bypass, encrypted password storage via Android Keystore, foreground VPN lifecycle and user-visible connection/error state.
- **ENGINE CHOICE FOR DOGFOOD** — `tun2proxy v0.8.3`, isolated behind `ProxyEngineAdapter`; upstream Android binaries are not committed and CI pins the upstream archive by SHA-256.
- **CI PASS / APK BUILT** — PR head has a successful mobile workflow and publishes a debug APK artifact.
- **PHYSICAL GATE OPEN** — before merge/closing APL-MOB-001: install on a real Android phone; verify SOCKS5 and the real HTTP proxy; wrong credentials/outage; browser + ordinary apps; sleep/wake; Wi-Fi↔cellular transitions; performance comparison; credential leakage inspection.
- **POLICY** — Always-on/reconnect behavior remains deliberately undecided until physical dogfood evidence exists.

### iOS and later mobile work

- **FUTURE / AFTER ANDROID DOGFOOD + DESKTOP BASELINES** — build iOS application using the same product model where platform APIs permit it.
- **FUTURE** — APL-MOB-002 proxy pool/health checks/automatic failover after MVP semantics are proven.
- **CAPABILITY-DEPENDENT** — application-level selection/routing on iOS/Android only where the platform actually permits it; unsupported capabilities must be explicit in UX.

## 9. All currently available workstreams

The project now has multiple genuinely available branches of work from the current `0.2.5` baseline:

1. **[Linux / primary local] APL-LNX-010 real Astra acceptance — DONE.** Physical Astra Linux SE acceptance closed Gate R8 and produced the first APL-REG-001C trusted-OS record.
2. **[Registry / physical] APL-REG-001C RED OS second record — PHYSICAL ENVIRONMENT REQUIRED.** Native RPM packaging plus strict RED OS evidence tooling are prepared in draft PR #70; install the accepted RED OS target and run the exact real-host protocol before resuming compatibility-dependent registry work.
3. **[Android / product dogfood] APL-MOB-001 PR #53 — READY NOW FOR PHYSICAL PHONE TESTING.** CI/APK exist; the remaining gate is real-device acceptance.
4. **[Windows trust / parallel] APL-REL-016 — READY NOW.** Choose future Windows public-trust/distribution architecture for `0.2.6+`, Russia-first, without mutating `v0.2.5`.
5. **[IP/legal / parallel] APL-IP-001 issue #57 — READY FOR FINAL HUMAN REVIEW.** Exact-object engineering and private rights evidence exist; canonical sign-off is still NOT APPROVED until an authorized human closes R-1..R-4 and selects the final decision.
6. **[Registry infrastructure / parallel] APL-REG-001B physical sovereign lifecycle evidence — READY WHEN INFRASTRUCTURE IS AVAILABLE.** Prove Russian-controlled authoritative source/build/artifact/distribution reality using the existing fail-closed tooling.
7. **[Product architecture / parallel] per-application routing — READY NOW FOR ARCHITECTURE DECISION.** Resolve the Windows native enforcement STOP-GATE before implementation/release.
8. **[Windows maintenance] `0.2.5` support/hotfix lane — AVAILABLE AS NEEDED.** Any changed product bytes require a new version and fresh exact-byte evidence rather than replacing `v0.2.5`.
9. **[macOS] production distribution hardening — AVAILABLE BUT DEFERRED.** Apple signing/notarization can be activated when macOS becomes a commercial priority.
10. **[Release] next SemVer release — AVAILABLE WHEN A MATERIAL CHANGE EXISTS.** Do not create `0.2.6` merely for docs; use it for a real trust/signing change, bug fix, routing increment or other product change.
11. **[iOS] mobile stage — FUTURE.** Start after Android dogfood and desktop baselines provide a stable product contract.
12. **[Registry docs/submission] APL-REG-001D/E/F — BLOCKED BY TWO-OS COMPATIBILITY GATE where dependent.** Resume after Astra + РЕД ОС acceptance and current-law recheck.

### Recommended execution order from 2026-09-14

1. **Install and execute the РЕД ОС real-host acceptance** required by APL-REG-001C using the prepared RPM/evidence lane in draft PR #70.
2. In parallel, **physically dogfood Android PR #53** on a real phone.
3. In parallel, close **APL-IP-001 human/legal sign-off** and resolve the prepared **APL-REL-016** owner decision packet.
4. Resolve the prepared **Windows per-application routing architecture** owner decision packet before native enforcement implementation.
5. Once both Russian OS acceptance records exist, resume APL-REG-001C compatibility reconciliation and then APL-REG-001D/F registry preparation.
6. Choose the next major desktop feature increment: **Windows per-application routing** versus **macOS production distribution**, based on commercial priority.
7. Cut the next SemVer release only for a material product/trust change.
8. Move from Android dogfood to polished Android MVP, then iOS, after physical evidence supports the architecture.

## 10. Platform / distribution matrix

| Platform / form | Current state | Next gate |
| --- | --- | --- |
| Windows installer | **PUBLISHED 0.2.5** | REL-016 only for future native Windows trust; otherwise maintenance |
| Windows portable | **PUBLISHED 0.2.5** | Maintenance / future feature release |
| Linux Debian `.deb` | **ENGINEERING + PHYSICAL ASTRA PASS** | Maintenance / regression |
| Linux on Astra Linux SE | **PHYSICAL PASS / GATE R8 DONE** | Maintenance / regression |
| Linux on РЕД ОС | **RPM + ACCEPTANCE TOOLING PREPARED / PHYSICAL RUN PENDING** | Install RED OS and complete second APL-REG-001C real-host record |
| Linux AppImage | **ENGINEERING DONE / COMMERCIAL HOLD** | Separate compliance clearance before promotion |
| macOS `.app` / DMG | **ENGINEERING/ACCEPTANCE DONE** | Apple production signing/notarization when prioritized |
| macOS portable | **OPTIONAL FUTURE** | Implement only if technically/product-wise useful |
| Android | **ACTIVE DOGFOOD / DRAFT PR #53** | Physical phone acceptance, then merge/polish MVP |
| iOS | **FUTURE** | Mobile-stage architecture after Android dogfood / desktop stability |

## Completion discipline

Do not substitute CI for physical App Control/Astra/РЕД ОС/mobile-device evidence, detached Russian release evidence for Microsoft native Windows publisher trust, or automation for human/legal decisions. Do not rewrite historical repository identities where they are part of provenance. Do not retarget immutable tags or replace published release assets in place. A documentation-only commit does not create a new product candidate. Current operational references must resolve to `arvectum2/proxy-launcher`.
