# Arvectum Proxy Launcher — canonical roadmap

Updated: 2026-09-29
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

Current canonical main verified before this roadmap update: e27d391259a436cc3ed7802c17f2e49787f13528.
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
- **NEXT DIRECT DESKTOP RELEASE — MANDATORY macOS recovery inclusion (v0.2.17+).** Carry forward PR #203 (reserved wake-refresh fail-closed sentinel recovery) and PR #207 (exact-endpoint HTTP/HTTPS enable-bit drift recovery). Release acceptance must physically verify: APL start → induced exact-endpoint enable-bit drift → rollback exit 0 → all saved network services match the pre-APL snapshot → direct and ordinary HTTPS succeed → legacy 127.0.0.1:1080/8082 tunnel remains untouched. Do not ship the next direct macOS desktop build from a source point older than merge commit 46aef7ecfd165aa03145d2a74d4aba1ba44d972d.
- **MAC APP STORE — REMEDIATED / READY FOR HUMAN RESUBMISSION — v0.2.17 build 3.** The Store lane remains separate from immutable direct v0.2.16.
  - Initial build 1 was submitted on 2026-09-26 and rejected on 2026-09-28 under Guidelines 2.1.0 App Completeness and 2.4.5 Hardware Compatibility.
  - PR #223 merged the remediation to main at `ad09b2393def6c498daa8d67d2439b1d1aac9502`: passive launch no longer mutates Network Extension preferences, the Store help flow no longer advertises GitHub Releases/self-update behavior, and the Catalyst deployment baseline was corrected.
  - Build 2 was intentionally not reused because App Store Connect reported macOS 12.0 minimum for that already-uploaded artifact.
  - Corrected build 3 is ARM64 Mac Catalyst + PacketTunnel, signed/validated, with app and extension `LSMinimumSystemVersion=13.0`; Apple `altool --validate-app` returned VERIFY SUCCEEDED.
  - Physical development-signed smoke on Mac mini passed: launch succeeded and passive startup did not create an additional APL VPN configuration (1 -> 1).
  - App Store Connect has build 3 selected and VALID with `minOsVersion=13.0`, `lsMinimumSystemVersion=13.0`, `usesNonExemptEncryption=false`; Review Notes were updated for the rejection response.
  - **CURRENT ASC STATE:** version 0.2.17 is PREPARE_FOR_SUBMISSION while the prior review submission remains UNRESOLVED_ISSUES. Remaining gate is human App Store Connect workflow: resolve/edit the rejected item -> Add for Review -> Resubmit. Do not rebuild or re-upload build 3 unless Apple reports a new binary issue.
- **MANDATORY HELP UX — DONE / PHYSICAL PASS.** The standard macOS Help item opens bundled offline help.
  - Direct Developer ID builds may expose GitHub/release links appropriate to direct distribution.
  - Mac App Store builds must remain useful offline and rely on App Store update semantics; the build-3 remediation removes competing GitHub Releases/self-update language from the Store help flow.
  - Core offline sections remain: **Getting Started**, **status meanings**, **proxy formats**, **Troubleshooting**, **About & Privacy**.
  - No Store build may ship a competing self-updater.
- **OPTIONAL FUTURE** — keep `.app`/DMG as the normal direct macOS distribution lane; add a separate portable form only if it provides real benefit without weakening recovery/update semantics.

## 7. Per-application routing — application exclusions and desktop enforcement

- **DONE** — APL-ROUTE-001 platform-neutral routing-rule model.
- **DONE** — APL-ROUTE-002 per-platform feasibility matrix.
- **AUTONOMOUS COMPLETE / LOCAL-NATIVE PENDING** — APL-ROUTE-003 Windows read-only/control-plane prototype.
- **DONE** — APL-ROUTE-004 durable ownership/recovery/security journal.
- **APPLICATION EXCLUSIONS CONTROL PLANE — IMPLEMENTED.** PR #183 added deterministic application-exclusion persistence/capability semantics plus Android live enforcement through `VpnService.Builder.addDisallowedApplication`.
- **ANDROID UI / CURRENT MAIN — 0.1.38 / versionCode 39.** The accepted adaptive/profile/application-exclusion baseline is retained; PR #221 layers the current public/private Android distribution flavors on top without regressing manual profiles, Auto, site exclusions or application exclusions.
- **iOS CONSUMER PATH — SHORTCUTS AUTOMATION.** Native unmanaged consumer iOS cannot truthfully offer arbitrary Per-App VPN selection; PRs #185/#187/#189 provide the supported consumer workaround using APL App Intents + Shortcuts Opened/Closed automations. Managed/MDM Per-App VPN remains a different future capability.
- **WINDOWS PRODUCTION ENFORCEMENT — OPTION A APPROVED / IN PROGRESS.** On 2026-09-29 the Owner explicitly started Windows Per-App routing, lifting the PR #144 stop-gate in favor of an Arvectum-owned WFP ALE callout + narrow privileged service + local proxy.
- **INITIAL SCOPE** — production protocol v1 admits `all`/CIDR selectors only. Domain selectors remain fail-closed until a DNS-aware lifecycle exists. The bounded service contract and ownership-before-mutation controller are implemented; live WFP callout/service enforcement still requires native build/install and real-Windows acceptance before capability may report supported.
- **ANDROID ACCEPTANCE BOUNDARY** — implementation and UI are merged, but do not invent the dedicated public-IP bypass proof if it has not been recorded separately.
- **APL-UI-001 GATE — DONE.** The cross-platform Adaptive UI was merged in PR #193 by explicit Owner decision; the remaining unavailable physical-platform acceptance was waived for that merge only and is not claimed as performed.

## 7A. Cross-platform Adaptive UI — APL-UI-001 — DONE / MERGED

Design decision source: `docs/APL_UI_UX_CROSSCHECK_20260926.md`.

- Shared navy/mint tokens, profile/exclusion language, connection-state semantics and one stateful primary Connect/Disconnect action are implemented across supported UI families.
- Mobile remains touch-first; desktop uses compact sidebar/desktop composition and native platform conventions.
- Top-level information model is Home, Profiles, Activity/Diagnostics and Settings.
- macOS recovery-state Home CTA was corrected during physical review.
- Focused desktop/UI regression suite passed 53/53; exact-head cross-platform/security CI was green.
- PR #193 merged on 2026-09-27 after explicit Owner instruction. Unperformed host-specific acceptance is not relabeled as PASS.

## 8. Mobile applications

### Android — GitHub public 0.1.19 / current-main + RuStore candidate 0.1.38 (39)

- **GITHUB/GITVERSE PUBLIC BASELINE — android-v0.1.19.** This remains the latest published Android release in those channels until a separate publication task creates a later release.
- **CURRENT MAIN — 0.1.38 / versionCode 39.** PR #221 merged the combined RuStore source to main at `676a987105d8f01b8ed32db8b500b58a26e74542`.
- **PUBLIC FLAVOR — ADS ENABLED.** The public flavor includes Yandex Mobile Ads App Open integration using RuStore block `R-M-20130429-1`.
- **PRIVATE FLAVOR — AD-FREE.** A distinct private flavor/package identity is present in the same codebase and does not include the ad integration; separate private distribution remains a delivery concern, not a second divergent application.
- **NO FRIEND/FREE PROFILES IN THE PUBLIC APP.** PR #221 removed the friend/free gateway UX, `FreeGatewayClient`, free-session refresh/recovery behavior and obsolete persisted free selection from the Android public path.
- **CORE USER FEATURES RETAINED.** Manual user-supplied proxy profiles, Auto across user profiles, site exclusions, application exclusions, accepted adaptive UI fixes and VPN recovery behavior remain.
- **RUSTORE — SUBMITTED / WAITING FOR MODERATION.** Version 0.1.38 (39), package `ru.arvectum.proxylauncher`, production-signed APK SHA-256 `21519775dd098fba2c2389ced34e5e991bf3335b6a414af3561b298515f8d572`, audience 100%. Publication mode is **Manual after approval**.
- **HISTORICAL FREE-GATEWAY INFRA.** The prior RU/US friend-test gateway evidence is preserved as historical controlled-test infrastructure, but it is not part of the current public Android client path and must not be reintroduced without an explicit new product task.
- **NEXT GATE.** Wait for RuStore moderation. Any rejection remediation starts from current main; any later GitHub/GitVerse/site 0.1.38+ publication is a separate release task.

### iOS — current App Store review-fix: 0.1.36 build 37

- **OLD SUBMISSION REJECTED FOR INFORMATION.** The earlier 0.1.19 new-app submission received Apple Guideline 2.1 Information Needed: physical-device recording plus six product/setup/service/region/material questions.
- **CURRENT SOURCE — 0.1.36 build 37.** Adaptive UI and Shortcuts-based application routing are merged; PR #196 prepared the current App Store version and PR #197 added unsigned Release artifact CI.
- **PHYSICAL DEVICE PASS.** Exact current 0.1.36 (37) was development-signed, installed and launched on iPhone 13 running iOS 27.0.
- **APP STORE BINARY PASS.** The first distribution attempt inherited an unsupported hotspot-provider entitlement and failed Apple 90046; the same build 37 was then re-signed with only the required packet-tunnel-provider/App Group/Keychain entitlements.
- **CURRENT APPLE BUILD STATE — VALID / APP_STORE_ELIGIBLE.** Clean 0.1.36 build 37 upload completed without errors/warnings, export compliance is set, and the build is linked to App Store version 0.1.36.
- **CURRENT HUMAN BLOCKER — PHYSICAL SCREEN RECORDING.** The owner must record the current 0.1.36 flow on the iPhone and transfer the MOV to Mac mini. Then current screenshots can be extracted/replaced, the recording attached, Apple’s six questions answered and the version resubmitted.
- **DO NOT BUMP TO BUILD 38 BY DEFAULT.** Open PR #198 was created during the earlier signing failure and is now superseded by the successful corrected build-37 upload unless Apple reports a new binary issue.
- **PRIVACY TRUTH** — Data Not Collected; no ads/analytics in this App Store candidate. Do not claim public availability before Apple approval.

## 9. Currently available workstreams

1. **[Desktop release] v0.2.16 — PUBLISHED / IMMUTABLE.** Windows/Astra/RED OS/AppImage plus Developer ID-signed/notarized Apple Silicon + Intel DMGs.
2. **[Android / RuStore] 0.1.38 (39) — SUBMITTED / WAITING FOR MODERATION.** Public flavor has Yandex App Open ads and no friend/free profiles; private flavor is ad-free. RuStore publication is manual after approval.
3. **[iOS App Store / HUMAN] 0.1.36 build 37 — VALID / APP_STORE_ELIGIBLE / BLOCKED ON PHYSICAL RECORDING.** After the recording arrives: replace screenshots, attach MOV, answer Guideline 2.1 and resubmit.
4. **[macOS App Store / HUMAN] 0.2.17 build 3 — VALID / PREPARE_FOR_SUBMISSION.** Remediation is merged and uploaded; finish only the App Store Connect resolve -> Add for Review -> Resubmit workflow. Do not rebuild/re-upload absent a new Apple binary issue.
5. **[Per-app Windows enforcement] Option A — IN PROGRESS.** Owner approval recorded 2026-09-29. Bounded service/ownership production foundation is being implemented from current main; native WFP callout/service plus real-Windows acceptance remain before live support.
6. **[Windows trust / REVIEW] APL-REL-016 — READY FOR REFRESH.** Latest substantive PR #161 remains version-stale against v0.2.16; future native signing starts with a new release, never by mutating v0.2.16.
7. **[Rospatent / HUMAN] program registration package — PREPARED / WAITING FOR APPLICANT FACTS.** PR #181 tracks the checkpoint; official filing/signature remains human.
8. **[Russian Software Register / HUMAN] dossier prepared on exact v0.2.9; external filing remains on hold for real private/infrastructure/signature gates.**
9. **[Adaptive UI] APL-UI-001 — DONE / MERGED #193.** It remains the shared current UI baseline, not an active implementation task.
10. **[Backlog-only] APL-NODE-001 and Arvectum Network remain intentionally absent from the primary roadmap and execution queue until explicit Owner reactivation.**

### Repository-hygiene note

Open PRs #81/#103/#132/#157 are superseded Windows-trust preparation history; #161 is the latest substantive stale trust packet. PR #68 is superseded by current per-app packet #144. Historical rollback/RED OS/mobile closeout branches remain non-authoritative where later merged work exists. Backlog-only paused initiatives are intentionally omitted from this primary roadmap.

### Execution order

- Follow the canonical `.agent/current-task.yaml` for the active user-facing workflow.
- **Android / RuStore:** do not rebuild or resubmit merely because moderation is pending. On RuStore feedback, start a new remediation task from current main and the exact 0.1.38 (39) artifact/source evidence. After approval, publication remains an explicit manual release decision.
- **macOS App Store:** corrected build 3 is already uploaded/selected. Complete only the human resolve -> Add for Review -> Resubmit flow; do not rebuild or re-upload unless Apple reports a new binary problem.
- **iOS App Store:** wait for the physical iPhone 13 / iOS 27 recording, then refresh screenshots/attachment, answer Guideline 2.1 and resubmit the already-valid build 37.
- **Windows per-app:** Option A is approved. Continue the smallest safe `all`/CIDR production slice; keep live capability disabled until native WFP service/callout installation and real-host recovery/security acceptance pass.
- **APL-REL-016:** safe REVIEW refresh remains available when prioritized.
- **Registry/Rospatent:** prepare evidence/forms as authorized, but final external signing/submission remains HUMAN.
- Paused backlog-only initiatives must not consume engineering time until the Owner explicitly restores them to the primary roadmap.
- **Proxy Launcher Watchdog remains outside this roadmap update and must not be enabled or modified by this task.**

## 10. Platform / distribution matrix

| Platform / form | Current state | Next gate |
| --- | --- | --- |
| Windows installer | **PUBLISHED v0.2.16** | Maintenance; Windows Authenticode remains a separate trust track |
| Windows portable | **PUBLISHED v0.2.16** | Maintenance / future feature release |
| Astra Linux .deb | **PUBLISHED v0.2.16 / PHYSICAL BASELINE PROVEN** | Rerun physical acceptance only for material platform/recovery or filing changes |
| RED OS .rpm | **PUBLISHED v0.2.16 / PHYSICAL BASELINE PROVEN** | Rerun physical acceptance only for material platform/recovery or filing changes |
| Linux AppImage | **PUBLISHED v0.2.16** | Maintain governed runtime/license/release parity |
| macOS .app / DMG | **PUBLISHED v0.2.16 / DEVELOPER ID + NOTARIZED** | Maintain exact-main ephemeral signing/notarization gate for future direct macOS releases |
| macOS Mac App Store | **0.2.17 build 3 VALID / PREPARE_FOR_SUBMISSION; rejection remediation merged/uploaded** | Human resolve rejected item -> Add for Review -> Resubmit; no rebuild unless Apple reports a new binary issue |
| Android | **GitHub/GitVerse 0.1.19 PUBLIC; current main + RuStore 0.1.38 (39) WAITING FOR MODERATION** | RuStore moderation -> explicit manual publication or targeted remediation; other channels require separate release task |
| iOS | **0.1.36 build 37 VALID / APP_STORE_ELIGIBLE; linked to App Store version; not resubmitted** | Physical iOS 27 recording -> current screenshots/attachment -> Guideline 2.1 reply -> resubmit |

## Completion discipline

Do not substitute CI for physical App Control/Astra/РЕД ОС/mobile-device evidence, detached Russian release evidence for Microsoft native Windows publisher trust, or automation for human/legal decisions. Do not rewrite historical repository identities where they are part of provenance. Do not retarget immutable tags or replace published release assets in place. A documentation-only commit does not create a new product candidate. Current operational references must resolve to `arvectum2/proxy-launcher`.
