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

## P8 — per-application routing / exclusions — IMPLEMENTED MOBILE CONTROL PLANE / WINDOWS OWNER GATE

Current Windows decision PR: `#144`. Stale predecessor #68 is superseded.

Completed:
- deterministic cross-platform application-exclusion persistence/capability model;
- Android live application bypass through VpnService;
- installed-app selection UI and controlled reconnect path;
- iOS capability truth: unmanaged consumer iOS does not pretend to support arbitrary native Per-App VPN selection;
- iOS consumer workaround implemented with App Intents + Shortcuts Opened/Closed automations;
- PR #144 reconciled to immutable `v0.2.16`/current-main, current application-exclusion work and APL-REL-016 dependency;
- PR #144 exact-head checks are green.

Current Windows stop-gate:
1. Owner/Product Owner explicitly selects or rejects the production architecture;
2. current technical recommendation is Option A — Arvectum-owned WFP ALE callout + narrow privileged service + local proxy;
3. no WFP filter/callout installation, privileged service mutation or production enforcement before that decision;
4. after approval, require real Windows recovery/security acceptance and a new release.

Android evidence boundary: merged implementation/current UI acceptance does not substitute for a separately documented public-IP bypass proof.

## P8A — APL-UI-001 cross-platform Adaptive UI — DONE / MERGED

- PR #193 merged the shared navy/mint design language, common IA and stateful connection action across UI families.
- macOS recovery-state Home CTA was fixed.
- focused desktop/UI regressions: 53/53 PASS;
- exact-head cross-platform/security CI green;
- Owner explicitly requested merge without waiting for unavailable/reproduction-only physical gates;
- waived/unperformed acceptance is not claimed as performed.

## P9 — macOS direct production distribution — DONE / PUBLISHED v0.2.16

- Developer ID Application signing is operational on the Arvectum-controlled Mac mini.
- ARM64 and Intel production DMGs were promoted from exact main, signed, Apple-notarized/stapled and Gatekeeper-verified.
- v0.2.16 publishes both notarized macOS DMGs alongside Windows/Linux artifacts.
- GitHub/GitVerse payload parity and release evidence are complete.
- Direct v0.2.16 is immutable and remains a separate supported distribution channel from the Mac App Store lane.
- **MANDATORY FOR THE NEXT DIRECT DESKTOP/macOS RELEASE (v0.2.17+):** include the macOS recovery fixes merged in PR #203 and PR #207. PR #207 / merge 46aef7ecfd165aa03145d2a74d4aba1ba44d972d adds safe rollback when HTTP/HTTPS Enabled bits drift off while host/port still exactly match APL or the saved snapshot; foreign host/port changes must remain fail-closed.
- **NEXT-RELEASE PHYSICAL GATE:** reproduce the enable-bit drift on a real Mac, require rollback exit 0, exact snapshot match for all saved services, working direct/ordinary HTTPS, and preservation of the independent legacy 127.0.0.1:1080/8082 tunnel.

Do not reopen the published v0.2.16 object. Apply the recovery acceptance above to the next direct release candidate instead.

## P9A — macOS App Store 0.2.17 + Help UX — SUBMITTED / WAITING FOR REVIEW / PR #175

Completed: isolated sandboxed ARM64 Catalyst + PacketTunnel lane; contract tests 9/9; provisioning/signing/archive/export/Apple validation/upload PASS; build 1 VALID / APP_STORE_ELIGIBLE; metadata, 4+ rating, Data Not Collected privacy, 175 territories and Mac screenshots complete; mandatory offline Help physically accepted; Packet Tunnel E2E physically accepted with HTTPS 200 and zero tunnel errors; version 0.2.17 build 1 submitted on 2026-09-26 and now WAITING FOR REVIEW.

Boundary: direct v0.2.16 remains immutable and separate. Do not rebuild, re-upload, withdraw or resubmit the Mac App Store version while review is pending unless Apple returns a concrete issue or the Owner requests a change.


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

### APL-MOB-004 Android monetization/distribution — PLANNED / OWNER-GATED

Free RU/US and managed-node functionality are separate from advertising/private-distribution decisions. No ad SDK/private-release infrastructure is authorized merely by those tracks.

### iOS App Store — 0.1.36 build 37 — VALID / APP_STORE_ELIGIBLE / HUMAN RECORDING BLOCKER

Canonical active checkpoint: `.agent/checkpoints/APL-IOS-APPREVIEW-FIX-20260926.yaml`.

History/current state:
- earlier 0.1.19 new-app submission was rejected under Guideline 2.1 Information Needed;
- Apple requested a physical-device screen recording and six information items;
- current source/version is 0.1.36 build 37 with Adaptive UI and Shortcuts-based app routing;
- PR #196 merged the current version; unsigned Release artifact CI is present on main;
- exact current app was physically installed/launched on iPhone 13 / iOS 27;
- first distribution attempt failed 90046 because the signature inherited unsupported hotspot-provider entitlement;
- the same build 37 was re-signed with narrow required entitlements only;
- clean build-37 upload completed without errors/warnings;
- App Store Connect reports build 37 VALID / APP_STORE_ELIGIBLE, export compliance false for non-exempt encryption and version relationship set to 0.1.36.

Remaining HUMAN step:
1. record current 0.1.36 flow on the physical iPhone from launch through selection/connect/traffic/disconnect;
2. transfer MOV to Mac mini;
3. extract current screenshots and replace old 0.1.19 screenshots;
4. attach the MOV to App Review;
5. reply to Apple’s six requested items;
6. resubmit/update review and verify resulting state.

Do not merge/use stale PR #198 build-38 bump unless Apple reports a new binary issue; corrected build 37 is already valid.

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
- PR #124 — stale APL-MOB-002 closeout branch; public Android is 0.1.19 and current-main Android is 0.1.36.
- PR #68 — superseded per-app routing decision preparation; current packet is PR #144.
- PR #198 — superseded build-38 bump; corrected iOS 0.1.36 build 37 is already VALID / APP_STORE_ELIGIBLE.
- PR #200 — superseded docs branch after its Arvectum Network roadmap is imported by the consolidated 2026-09-27 sync.
- PRs #90/#91/#92 — superseded Windows rollback implementations; merged PR #93/#94 and public `v0.2.9` are authoritative.
- PRs #70/#74/#82 — superseded RED OS preparation paths; merged PR #83 is authoritative.

These stale PRs are not product tracks and must not be resumed without reconciliation.

## Current execution view

- **DESKTOP STABLE:** v0.2.16 is public and immutable.
- **DIRECT macOS:** ARM64 + Intel Developer ID/notarized DMGs are public.
- **MAC APP STORE:** 0.2.17 build 1 submitted / Waiting for Review; physical Help and Packet Tunnel E2E complete.
- **ANDROID PUBLIC:** 0.1.19.
- **ANDROID CURRENT MAIN:** 0.1.36/versionCode 37 physically accepted for current adaptive UI; application-exclusion implementation is merged; no public 0.1.36 release.
- **iOS APP STORE:** 0.1.36 build 37 VALID / APP_STORE_ELIGIBLE; HUMAN blocker is one physical iOS 27 screen recording, then screenshots/review attachment/reply/resubmission.
- **APL-UI-001:** DONE / merged #193.
- **PER-APP WINDOWS:** PR #144 is already refreshed/green; now blocked only on explicit Owner architecture selection.
- **APL-NODE-001:** DEFERRED / PAUSED BY OWNER; Phase A and PR #195 are preserved in backlog, with no further engineering until explicit reactivation.
- **ARVECTUM NETWORK:** DEFERRED / PAUSED BY OWNER; detailed VPS-first plan remains in backlog/ARVECTUM_NETWORK_ROADMAP.md, with no infrastructure/legal/commercial execution until explicit reactivation.
- **FREE GATEWAY:** live controlled-test infrastructure; broad-public anti-abuse/quota hardening still pending.
- **APL-MOB-004:** PLANNED / OWNER-GATED.
- **APL-REL-016:** REVIEW refresh remains available when prioritized; it has no dependency on the paused APL-NODE-001 / Arvectum Network backlog tracks.
- **ROSPATENT:** working package prepared; waiting for applicant yellow-field facts; final filing HUMAN.
- **RUSSIAN SOFTWARE REGISTER:** repository dossier done on exact v0.2.9; external filing remains HUMAN HOLD.
- **PROXY LAUNCHER WATCHDOG:** intentionally not part of this update; do not enable it.

Current work order: follow the canonical active task and keep #144 at the Owner decision gate. APL-NODE-001 and Arvectum Network remain backlog-only; they are intentionally absent from the primary roadmap and execution queue until the Owner explicitly reactivates them.

## Completion discipline

Do not relabel CI as physical-host/device evidence, repository documentation as legal/corporate proof, detached Russian evidence as Microsoft native publisher trust, or automation as Owner/HUMAN approval. Published releases are immutable evidence objects; changed product bytes require a new version.
