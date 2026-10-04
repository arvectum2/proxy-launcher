# Arvectum Proxy Launcher — remaining local / human / infrastructure backlog

Updated: 2026-09-26  
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Current stable release: `v0.2.16`

This file contains the remaining work that cannot be truthfully completed by hosted repository automation alone, plus active review/owner gates after the Windows/Astra/RED OS desktop baseline and registry dossier work.

## P0 — repository / executor baseline — DONE

- **DONE** — canonical repository is `arvectum2/proxy-launcher`; migration recovery and main-protection acceptance are historical closure.
- **DONE** — the single hourly `Proxy Launcher Watchdog` is enabled and reads `.agent/executor-policy.yaml`, `.agent/execution-queue.yaml`, `.agent/current-task.yaml`, this backlog and the canonical roadmap.
- **RULE** — watchdog may skip blocked HUMAN/OWNER gates to do later independent admitted preparation, but may not reorder the queue or invent scope/approval.

## P1 — current stable release `v0.2.12` — PUBLISHED

Published 2026-09-21 from exact release SHA `8d9a4e5913fa92b39f0f926004df6f1fd57f3bde`:

- Windows x64 Setup;
- Windows x64 portable ZIP;
- Astra Linux x86-64 DEB;
- RED OS 8.0.3 x86-64 RPM;
- generic Linux x86-64 AppImage;
- `SHA256SUMS.txt`.

GitHub release assets independently pass `sha256sum -c`; GitVerse metadata/assets/canonical-payload parity is recorded PASS.

Important boundary: current `main` is `df4478a70729e20f33b7a0d17476183423955576`, ahead of the immutable v0.2.12 release because PR #148 later merged free-proxy gateway/Android 0.1.31 work. Do not describe those post-release bytes as part of v0.2.12.

Historical progression:
- `v0.2.5` — Windows CFA-safe physically accepted baseline;
- `v0.2.6` — Windows + Astra release lane;
- `v0.2.7` — RED OS release track;
- `v0.2.8` — Linux mixed-state recovery hardening;
- `v0.2.9` — Windows saved-or-Arvectum recovery symmetry;
- `v0.2.10` — AppImage promotion;
- `v0.2.11` — Windows PAC/WPAD isolation + macOS Safari CONNECT hardening;
- `v0.2.12` — verified macOS long-sleep recovery + Android long-sleep/foreground reconciliation.

v0.2.15 remains the immutable ad-hoc macOS baseline. v0.2.16 is now published with Developer ID signing, Apple notarization/stapling, Gatekeeper verification and GitVerse payload parity; v0.2.15 was not modified.

## P2 — Astra Linux / Gate R8 — DONE / PHYSICAL PASS

- **DONE** — real Astra Linux Special Edition 1.8/Fly physical-host acceptance.
- **PASS** — install, GUI/runtime, NetworkManager enable/disable, no-proxy sync, exact rollback, autostart, crash recovery, reboot recovery, package lifecycle, diagnostics/privacy and cleanup.
- **DONE** — APL-LNX-011 Firefox system-proxy fix closed by PR #71/#72.
- **CURRENT RELEASE** — `v0.2.16` ships the Astra DEB; v0.2.9 remains the filing-evidence baseline.

Astra acceptance remains a trusted-OS compatibility evidence record; an exact-`v0.2.9` rerun is future-proof evidence, not a currently represented 2026 filing prerequisite.

## P3 — RED OS / APL-REG-001C — DONE / PHYSICAL PASS

- **DONE** — RED OS 8.0.3 Standard Desktop x86_64 physical acceptance, merged by PR #83.
- **PASS** — clean install and RPM verification, start/stop, byte-exact KDE + NetworkManager rollback, Chromium system-PAC routing, localhost no-proxy, emergency rollback, XDG autostart ownership, diagnostics/no-mutation, full remove/reinstall and final restoration.
- **PASS** — focused RED OS regression suite `62/62`.
- **CURRENT RELEASE** — `v0.2.16` ships the RED OS RPM; v0.2.9 remains the filing-evidence baseline.

Open preparation PRs #70/#74/#82 are superseded by the completed PR #83 path and are not active roadmap tracks.

## P4 — mobile + free-location track

### Android public baseline — `android-v0.1.19`

- **PUBLIC / MIRRORED** — Android 0.1.19 remains the latest explicitly published Android release.
- Earlier transport/multiprofile, Auto failover/network handoff, site exclusions and sleep/wake work remain historical accepted foundations.

### Free RU/US gateway — DONE / LIVE CONTROLLED-TEST INFRA

- supplier proxy credentials remain server-side;
- clients receive short-lived Arvectum gateway sessions and public location metadata;
- real RU→RU and US→US checks/soak passed;
- broad anonymous rollout still requires per-install quota/rate-limit/anti-abuse hardening.

### Android current main — 0.1.36 / versionCode 37 — PHYSICAL UI ACCEPTANCE PASS / NOT PUBLIC

Merged path: application exclusions #183, UX fixes #190, Adaptive UI #193.

Current facts:
- installed-app exclusion selection is implemented and persisted;
- Android VpnService applies selected app bypass via `addDisallowedApplication` and reconnects in a controlled way;
- connected active-profile editing, app-list async loading/error handling and adaptive New/Edit actions are merged;
- owner physically accepted the final 0.1.36 adaptive action rendering;
- post-merge Android CI passed;
- public Android release remains 0.1.19.

Acceptance boundary:
- do not manufacture a dedicated public-IP routing proof for application bypass if it has not been separately recorded;
- current-main 0.1.36 acceptance does not itself publish an APK/tag.

### APL-MOB-004 — PLANNED / OWNER PRIORITY + PACKAGE-IDENTITY GATE

This remains a separate monetization/distribution track:
- public ads-enabled channel planned for GitHub/GitVerse/site/RuStore;
- initial ad target Yandex Mobile Ads / App Open;
- private no-ads artifact from same codebase via build configuration/flavor;
- Owner must decide private package/update semantics and explicitly authorize provider/configuration work before implementation.

## P5 — IP / corporate rights boundary — DONE FOR CURRENT FILING EVIDENCE

Current final object: exact public `v0.2.9`.

Repository engineering and Owner-factual evidence are complete for the current filing packet:

- exact source/tag tree, promoted package digests, provenance and CycloneDX SBOM are governed;
- v0.2.5 -> v0.2.9 material drift is reconciled;
- the executed 2026-09-14 private sole-participant/rightsholder decision remains the operative chain-of-title evidence;
- the actual instrument was reviewed and identifies Arvectum Proxy Launcher without a version number, transfers the exclusive right in full and authorizes modification/reworking;
- current Rospatent, corporate/Russian-control and human creative-control facts were confirmed by the Owner;
- historical v0.2.9 filing scope: Windows Setup/portable, Astra DEB and RED OS RPM;
- Owner directive 2026-09-18 separately admits AppImage for the next release. This does not alter the exact v0.2.9 filing-evidence object or its already executed rights record.

The previously prepared R-1B two-party/future-rights agreement is **not required to complete this project filing-evidence task** and must not be presented to the Owner as a mandatory signature step. It is retained only as optional external legal hardening. A future registry/expert clarification or external-counsel review may still recommend a separate instrument for later human-authored copyrightable contributions.

Issue: `#57`. Current record: `docs/APL_IP_001_V0_2_9_SIGNOFF.md`.

### AppImage lane — DONE / PUBLISHED IN v0.2.10

PR #111 promoted the governed APL-LNX-008 AppImage lane into the canonical release set, and public v0.2.10 includes the x86_64 AppImage plus checksum coverage. The pinned type-2 runtime/source identity and runtime/third-party notices remain part of the packaging contract. DEB/RPM remain native preferred Linux packages.

## P6 — Russian Software Register sovereign lifecycle — BLOCKED / PHYSICAL INFRASTRUCTURE

APL-REG-001B repository tooling exists, but filing-grade physical proof remains open.

Required real chain:

`Russian authoritative source -> Russian-controlled source/object storage -> Russian build/compilation host -> governed/offline inputs -> exact artifacts -> Russian authoritative release/distribution storage -> evidence bundle`.

Do not claim GitVerse or another provider is compliant merely because it is Russian. GitHub remains useful for development/public distribution but does not substitute for the required physical lifecycle facts.

Issue: `#55`.

## P7 — Windows public trust / APL-REL-016 — READY FOR REVIEW REFRESH

Issue: `#30`. Latest substantive review PR: `#161`.

Historical preparation PRs #132 and #157 are superseded. PR #161 contains the latest substantive Windows public-trust packet, but it too is version-stale:
- its branch was prepared before immutable v0.2.16 became current;
- public v0.2.16 ships without native Windows Authenticode;
- therefore the first eligible future native Authenticode/public-trust release is now **v0.2.17+**.

Current action:
1. refresh/rebase #161 from current main against immutable `v0.2.16`;
2. set `v0.2.17+` as the first eligible future Windows native-signing release;
3. re-verify SmartScreen/App Reputation, Smart App Control/Application Control, managed-enterprise trust, CA/B Forum and provider geography requirements;
4. keep Russian detached CryptoPro/Rutoken evidence separate from Microsoft-native publisher trust;
5. stop at Owner review.

Provider/certificate spend, key custody, production signing, approval/merge of the decision packet and release remain Owner-reserved.

## P8 — per-application routing / exclusions — IMPLEMENTED / WINDOWS PHYSICAL PASS

Completed:
- deterministic cross-platform application-exclusion persistence/capability model;
- Android live application bypass through VpnService plus installed-app selection UI and controlled reconnect;
- iOS capability truth plus consumer workaround through App Intents + Shortcuts Opened/Closed automations;
- Owner selected the official signed WinDivert 2.2.2 production architecture; the custom Arvectum WFP callout path is lab-only;
- PR #241 merged the production WinDivert routing implementation;
- PR #243 merged the physical-installer ProgramData compatibility fix;
- PR #244 records closure of the old architecture gate;
- exact-head Windows installer/portable/WinDivert/public-trust CI passed;
- physical Windows acceptance proved GUI-selected DIRECT vs unselected PROXY routing, rule changes, disconnect/reconnect, forced-crash rollback and active-session reboot recovery.

Current boundary:
1. published v0.2.16 is immutable and does not contain this later per-app implementation;
2. shipping WinDivert per-app routing requires a new explicit Windows desktop release and release acceptance;
3. do not revive custom WFP for production or procure a custom kernel-driver signing path without a new Owner decision;
4. Android public-IP bypass proof remains a separate evidence boundary where not already documented.

## P8A — APL-UI-001 cross-platform Adaptive UI — DONE / MERGED

- PR #193 merged the shared navy/mint design language, common IA and stateful connection action across UI families.
- macOS recovery-state Home CTA was fixed.
- focused desktop/UI regressions: 53/53 PASS;
- exact-head cross-platform/security CI green;
- Owner explicitly requested merge without waiting for unavailable/reproduction-only physical gates;
- waived/unperformed acceptance is not claimed as performed.

## P8B — APL-CONNECT-001 universal connection input — PRODUCT-APPROVED / NOT STARTED

Product direction is approved, but implementation is not yet prioritized into the execution queue.

Staged delivery:
1. **Stage A:** universal importer shell for proxy text/URLs, clipboard, QR and deep links; MTProto detection + Telegram handoff; preserve current HTTP/SOCKS/HTTPS engines.
2. **Stage B:** VLESS + Reality full-tunnel support with selected/pinned engine, secure storage and physical cross-platform validation.
3. **Stage C:** managed subscriptions with validated refresh, last-known-good rollback and explicit provider/source identity.
4. **Stage D:** Marketplace zero-config provisioning so purchased/issued connections appear in APL without manual credential entry.
5. **Stage E:** demand-driven compatibility expansion, beginning with WireGuard/AmneziaWG.

Required product rules: keep the default UX simple, keep imported secrets local-first, make export/share of secrets explicit, and do not market unsupported opaque configs or MTProto as device-wide VPN.

## P9 — macOS direct production distribution — DONE / PUBLISHED v0.2.16

- Developer ID Application signing is operational on the Arvectum-controlled Mac mini.
- ARM64 and Intel production DMGs were promoted from exact main, signed, Apple-notarized/stapled and Gatekeeper-verified.
- v0.2.16 publishes both notarized macOS DMGs alongside Windows/Linux artifacts.
- GitHub/GitVerse payload parity and release evidence are complete.
- Direct v0.2.16 is immutable and remains a separate supported distribution channel from the Mac App Store lane.
- **MANDATORY FOR THE NEXT DIRECT DESKTOP/macOS RELEASE (v0.2.17+):** include the macOS recovery fixes merged in PR #203 and PR #207. PR #207 / merge 46aef7ecfd165aa03145d2a74d4aba1ba44d972d adds safe rollback when HTTP/HTTPS Enabled bits drift off while host/port still exactly match APL or the saved snapshot; foreign host/port changes must remain fail-closed.
- **NEXT-RELEASE PHYSICAL GATE:** reproduce the enable-bit drift on a real Mac, require rollback exit 0, exact snapshot match for all saved services, working direct/ordinary HTTPS, and preservation of the independent legacy 127.0.0.1:1080/8082 tunnel.

Do not reopen the published v0.2.16 object. Apply the recovery acceptance above to the next direct release candidate instead.

## P9A — macOS App Store 0.2.17 build 3 — RESUBMITTED / WAITING FOR REVIEW

Completed:
- isolated sandboxed ARM64 Catalyst + PacketTunnel lane, provisioning/signing/archive/export/Apple validation and physical Packet Tunnel E2E;
- initial build 1 review and 2026-09-28 rejection remediation in PR #223;
- corrected build 3 with macOS 13.0 minimum, VALID / APP_STORE_ELIGIBLE, passive-launch physical smoke PASS;
- 2026-10-01 follow-up review issues were metadata/reviewer-information only: Apple product naming, reviewer access and VPN/data-handling questions;
- on 2026-10-02 Store name changed to `Proxy Launcher by Arvectum`, reviewer-access instructions and direct VPN/data answers were added, the reviewer reply was sent, and the existing build 3 submission was resolved/resubmitted without a binary rebuild;
- final verified App Store Connect state: app version 0.2.17 (3) and review submission `WAITING_FOR_REVIEW`.

Current boundary: wait for Apple feedback. Do not rebuild, re-upload, withdraw or bump build 3 solely because review is pending. Start a new task only if Apple returns a concrete new issue.

## P10 — Russian Software Register dossier / external filing — DOSSIER DONE, SUBMISSION HOLD

### Repository dossier — DONE

APL-REG-001D was merged by PR #95 with final checkpoint PR #96.

Prepared under `docs/registry/` for `v0.2.9` / class `02.02 — Программы обслуживания`:

- application-field worksheet;
- Rule 1236 matrix;
- functional characteristics;
- install/operation/removal/recovery manual;
- support/maintenance statement;
- lifecycle/infrastructure statement;
- licensing/price statement;
- expert verification procedure;
- private-evidence checklist;
- pre-submission audit.

Focused dossier tests: `6/6 PASS`. Exact-head GitHub workflows: `10/10 SUCCESS`.

### External filing — PRE-SUBMISSION / HOLD

Before signing/submission, close all real gates:

1. P5 rights/corporate evidence;
2. applicable foreign-payment/accounting evidence;
3. P6 physical Russian lifecycle proof;
4. factual Russian support/modification entity/person and official contacts;
5. final exact-`v0.2.9` Russian-GUI visual review;
6. current corporate facts and signer authority;
7. qualified electronic signature / УКЭП;
8. live law/classifier/portal recheck immediately before filing.

Automation must never sign or submit the application.

Under the official baseline rechecked 2026-09-17, the two-trusted-OS condition for class 02.02 starts on **2027-01-01**. Existing Astra + RED OS physical acceptance is retained as future-proof compatibility evidence; exact-`v0.2.9` reruns remain preferred but are not represented as a current 2026 filing blocker.

## P11 — mobile store stages

### Android / RuStore — 0.1.38 (39) — SUBMITTED / WAITING FOR MODERATION

- PR #221 merged the current Android source baseline.
- Public flavor includes Yandex App Open advertising; private flavor remains ad-free with a distinct package identity.
- Friend/free gateway UX and client behavior are absent from the current public app.
- Manual user profiles, Auto, site exclusions, application exclusions, adaptive UI and recovery remain.
- Production RuStore APK 0.1.38 (39) is submitted; publication mode is Manual after approval.
- Current action: wait for moderation. On rejection, start targeted remediation from current main; on approval, perform the explicit manual publication action.

### iOS App Store — 0.1.36 build 40 — RESUBMITTED / WAITING FOR REVIEW

Completed:
- current 0.1.36 review binary uses build 40 with Adaptive UI and Shortcuts-based application routing;
- physical-device review recording is attached;
- current entitlement scope is accepted and no binary defect is presently identified;
- Apple VPN/data-handling questions were answered and public privacy wording clarified;
- Apple business-model questions were answered: the app does not sell/unlock paid digital content or proxies and users supply their own connection parameters;
- existing review item was resubmitted without a speculative build bump;
- final verified state is `WAITING_FOR_REVIEW`.

Current action: wait for Apple feedback. Do not rebuild/resubmit build 40 unless Apple identifies a concrete new issue.

## P12 — APL-NODE-001 managed proxy infrastructure — DEFERRED / PAUSED BY OWNER

Paused by Owner on 2026-09-29. Preserve all existing Phase A work and context below, but do not continue implementation, merge PR #195 or provision real infrastructure until explicitly reactivated.

Phase A implemented in PR #195:
- provider-neutral Transport / ExitClass / ProductSpec / ManagedNode / ManagedAccess contracts;
- capacity-aware deterministic node selection;
- unique per-user credential issuance;
- VLESS/REALITY client URI + Xray server config rendering;
- REALITY private key stays server-side;
- generated config uses current Xray terminology/schema;
- focused managed-node + free-gateway suite 21/21 PASS; py_compile and diff checks PASS;
- official Xray v26.9.9 binary/version/x25519 generation verified.

Deferred resume queue (do not execute while paused):
1. exact `xray run -test` on generated config in an environment that permits it;
2. Android managed VLESS/REALITY profile consumption without breaking manual proxy types;
3. iOS managed profile transport integration;
4. Owner provisions one EU test node;
5. real-device E2E + sleep/wake/reconnect + CPU/throughput/session/traffic measurements;
6. use measurements to set initial Shared/Private/Dedicated density/economics.

Hard boundary: no automatic VPS/IP/provider purchase, production mutation, billing or public sale.

## P13 — Arvectum Network commercial infrastructure — DEFERRED / PAUSED BY OWNER

Paused by Owner on 2026-09-29. Detailed checklist remains preserved in `ARVECTUM_NETWORK_ROADMAP.md`; no infrastructure/legal/commercial execution should continue until explicit reactivation.

Fixed decisions:
- VPS-first MVP; third-party proxy supplier marketplace deferred;
- Russian control plane and primary production customer DB in Russia;
- self-host PostgreSQL on Moscow VPS for MVP; Managed PostgreSQL deferred;
- Mac mini remains development/build/admin, not production customer database;
- first foreign pilot node is Frankfurt;
- scale to Netherlands/Kazakhstan/Finland/second provider only after Germany E2E/load evidence.

Current factual state:
- corporate Timeweb Cloud account is created;
- Moscow control VPS and Frankfurt node are not yet treated as purchased/provisioned;
- target Moscow MVP sizing: 2 vCPU / 4 GB / 50 GB;
- Roskomnadzor operator notification/responsible-person/final hosting-location facts remain HUMAN/legal work.

Deferred resume queue (do not execute while paused):
1. provision/harden Moscow control plane and self-hosted PostgreSQL + encrypted backups/restore drill;
2. reconcile privacy policy and complete required personal-data operator steps;
3. deploy Frankfurt pilot and technical per-user credentials/telemetry;
4. validate APL→control plane→Germany→Internet E2E, failure/recovery and load/capacity;
5. only then add billing/commercial pilot;
6. only after a working own network add supplier marketplace layers.

## P14 — Rospatent program registration — PACKAGE PREPARED / HUMAN INPUT BLOCKED

Tracking PR: `#181`. Filing object: exact `v0.2.16` / release commit `6799297bf1492d352ca9d78a0a49b2adf3345d2a`.

Prepared:
- current official Rospatent/FIPS requirements and 5000 RUB fee rechecked;
- applicant public corporate data verified;
- 6-page working DOCX prepared/rendered/visually checked;
- unknown author/personal/right-chain/funding/release-country/signature fields intentionally blank and yellow.

Next:
- applicant fills yellow factual fields;
- then prepare official application/author-consent forms and exact-v0.2.16 deposited source fragments;
- final electronic signing/submission remains HUMAN.

## Maintenance / repository hygiene

- PR #80 — release-evidence workflow maintenance; reconcile with current `main` before merge.
- PR #81/#103/#132/#157 — superseded older APL-REL-016 preparations; PR #161 is the latest substantive but version-stale trust packet to refresh against v0.2.16.
- PR #113 — redundant AppImage closeout branch overtaken by merged PR #112.
- PR #117 — redundant Android 0.1.13 closeout overtaken by merged PR #118.
- PR #120 — superseded continuous-failover development branch overtaken by merged PR #119.
- PR #124 — stale APL-MOB-002 closeout branch; public GitHub/GitVerse Android remains 0.1.19 while current-main/RuStore Android is 0.1.38 (39).
- PR #68/#144 — superseded Windows per-app recommendation/decision preparation; merged PR #241/#243 plus gate-closing PR #244 are authoritative.
- PR #198 — superseded build-38 bump; current App Store review binary is iOS 0.1.36 build 40 and is WAITING_FOR_REVIEW.
- PR #200 — superseded docs branch after its Arvectum Network roadmap is imported by the consolidated 2026-09-27 sync.
- PRs #90/#91/#92 — superseded Windows rollback implementations; merged PR #93/#94 and public `v0.2.9` are authoritative.
- PRs #70/#74/#82 — superseded RED OS preparation paths; merged PR #83 is authoritative.

These stale PRs are not product tracks and must not be resumed without reconciliation.

## Current execution view

- **DESKTOP STABLE:** v0.2.16 is public and immutable.
- **DIRECT macOS:** ARM64 + Intel Developer ID/notarized DMGs are public; the next direct release must carry the merged macOS recovery fixes and physical recovery acceptance.
- **MAC APP STORE:** 0.2.17 build 3 is `WAITING_FOR_REVIEW` after the 2026-10-02 metadata/reviewer-access/VPN-data remediation and resubmission.
- **ANDROID:** GitHub/GitVerse public baseline remains 0.1.19; current main/RuStore candidate is 0.1.38 (39), submitted and waiting for moderation with manual publication after approval.
- **iOS APP STORE:** 0.1.36 build 40 is `WAITING_FOR_REVIEW`; physical review recording and required information responses are already supplied.
- **APL-UI-001:** DONE / merged #193.
- **PER-APP WINDOWS:** production WinDivert 2.2.2 implementation is merged and physically accepted on current main; old WFP owner gate is closed. Shipping waits for a new explicit desktop release.
- **APL-CONNECT-001:** PRODUCT-APPROVED / NOT STARTED; Stage A universal importer/MTProto handoff is the first implementation step when prioritized.
- **APL-REL-016:** REVIEW refresh remains available when prioritized; PR #161 is version-stale against v0.2.16.
- **ROSPATENT:** working package prepared; waiting for applicant yellow-field facts; final filing HUMAN.
- **RUSSIAN SOFTWARE REGISTER:** repository dossier done on exact v0.2.9; external filing remains HUMAN HOLD, chiefly on sovereign lifecycle/private/signature evidence.
- **APL-NODE-001:** DEFERRED / PAUSED BY OWNER; preserve existing Phase A/PR #195 and do not resume without explicit reactivation.
- **ARVECTUM NETWORK:** DEFERRED / PAUSED BY OWNER; do not provision infrastructure or restart commercial/legal work without explicit reactivation.
- **FREE GATEWAY:** historical controlled-test infrastructure only; current public Android does not use it.
- **PROXY LAUNCHER WATCHDOG:** outside this roadmap sync; do not modify its state here.

Current work order is event-driven for the stores (wait for Apple/RuStore), while autonomous engineering can proceed on explicitly prioritized ready tracks such as APL-REL-016, a new direct desktop release, or APL-CONNECT-001. APL-NODE-001 and Arvectum Network remain backlog-only.

## Completion discipline

Do not relabel CI as physical-host/device evidence, repository documentation as legal/corporate proof, detached Russian evidence as Microsoft native publisher trust, or automation as Owner/HUMAN approval. Published releases are immutable evidence objects; changed product bytes require a new version.
