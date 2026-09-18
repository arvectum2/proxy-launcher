# Arvectum Proxy Launcher — remaining local / human / infrastructure backlog

Updated: 2026-09-18  
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Current stable release: `v0.2.9`

This file contains the remaining work that cannot be truthfully completed by hosted repository automation alone, plus active review/owner gates after the Windows/Astra/RED OS desktop baseline and registry dossier work.

## P0 — repository / executor baseline — DONE

- **DONE** — canonical repository is `arvectum2/proxy-launcher`; migration recovery and main-protection acceptance are historical closure.
- **DONE** — the single hourly `Proxy Launcher Watchdog` is enabled and reads `.agent/executor-policy.yaml`, `.agent/execution-queue.yaml`, `.agent/current-task.yaml`, this backlog and the canonical roadmap.
- **RULE** — watchdog may skip blocked HUMAN/OWNER gates to do later independent admitted preparation, but may not reorder the queue or invent scope/approval.

## P1 — current stable release `v0.2.9` — PUBLISHED

Published 2026-09-17:

- Windows x64 Setup;
- Windows x64 portable ZIP;
- Astra Linux x86-64 DEB;
- RED OS 8.0.3 x86-64 RPM;
- `SHA256SUMS.txt`.

`v0.2.9` closes the Windows rollback-ownership asymmetry found during cross-platform recovery comparison. Third/foreign system-proxy state now fails closed rather than being silently overwritten.

Historical progression retained for provenance:

- `v0.2.5` — Windows CFA-safe physically accepted baseline;
- `v0.2.6` — Windows + Astra release lane;
- `v0.2.7` — RED OS release track;
- `v0.2.8` — Linux mixed-state recovery hardening;
- `v0.2.9` — Windows saved-or-Arvectum recovery symmetry.

## P2 — Astra Linux / Gate R8 — DONE / PHYSICAL PASS

- **DONE** — real Astra Linux Special Edition 1.8/Fly physical-host acceptance.
- **PASS** — install, GUI/runtime, NetworkManager enable/disable, no-proxy sync, exact rollback, autostart, crash recovery, reboot recovery, package lifecycle, diagnostics/privacy and cleanup.
- **DONE** — APL-LNX-011 Firefox system-proxy fix closed by PR #71/#72.
- **CURRENT RELEASE** — `v0.2.9` ships the Astra DEB.

Astra acceptance remains a trusted-OS compatibility evidence record; an exact-`v0.2.9` rerun is future-proof evidence, not a currently represented 2026 filing prerequisite.

## P3 — RED OS / APL-REG-001C — DONE / PHYSICAL PASS

- **DONE** — RED OS 8.0.3 Standard Desktop x86_64 physical acceptance, merged by PR #83.
- **PASS** — clean install and RPM verification, start/stop, byte-exact KDE + NetworkManager rollback, Chromium system-PAC routing, localhost no-proxy, emergency rollback, XDG autostart ownership, diagnostics/no-mutation, full remove/reinstall and final restoration.
- **PASS** — focused RED OS regression suite `62/62`.
- **CURRENT RELEASE** — `v0.2.9` ships the RED OS RPM.

Open preparation PRs #70/#74/#82 are superseded by the completed PR #83 path and are not active roadmap tracks.

## P4 — Android mobile dogfood — APL-MOB-001 DONE / APL-MOB-002 IN PROGRESS

### APL-MOB-001 Android lane — DONE

- **MERGED / PHYSICAL** — PR #53 established the physically accepted 0.1.4 VpnService/TUN baseline with real HTTP/HTTPS CONNECT routing, public-IP change and lifecycle checks.
- **MERGED / PHYSICAL** — PR #104 added 0.1.5 multiprofile migration/save/select/delete and passed its physical upgrade/two-profile selection gate.
- The Android APL-MOB-001 dogfood prerequisite for APL-MOB-002 is therefore closed. Issue #50 may still carry broader cross-platform/mobile scope; do not reinterpret that as an unpassed Android baseline.

### APL-MOB-002 — IN PROGRESS / HUMAN GATE

Draft PR: `#105`, branch `apl-mob-002-android-auto-switch`.

Already recorded as physically accepted in the PR:
- connected manual A → B hot switch through app-managed disconnect/select/reconnect;
- pool-level **Auto** selection distinct from per-profile protocol Auto;
- bounded candidate probing and selection of a working saved proxy;
- status naming the concrete Auto-selected profile/transport.

Current 0.1.7 physical gate before merge:
1. install over the accepted previous build;
2. verify the Auto screen hides host/port/login/password/protocol editor fields;
3. verify New/named profiles still expose editing while disconnected;
4. verify Arvectum header/status/card/power-button rendering and visible press feedback;
5. verify the adaptive launcher icon is full-size and unclipped;
6. rerun networking/hot-switch regression.

Continuous background failover after an already-connected upstream later dies remains a later APL-MOB-002 slice.

## P5 — IP / corporate rights boundary — DONE FOR CURRENT FILING EVIDENCE

Current final object: exact public `v0.2.9`.

Repository engineering and Owner-factual evidence are complete for the current filing packet:

- exact source/tag tree, promoted package digests, provenance and CycloneDX SBOM are governed;
- v0.2.5 -> v0.2.9 material drift is reconciled;
- the executed 2026-09-14 private sole-participant/rightsholder decision remains the operative chain-of-title evidence;
- the actual instrument was reviewed and identifies Arvectum Proxy Launcher without a version number, transfers the exclusive right in full and authorizes modification/reworking;
- current Rospatent, corporate/Russian-control and human creative-control facts were confirmed by the Owner;
- approved current scope: Windows Setup/portable, Astra DEB and RED OS RPM; AppImage excluded from the current scope only.

The previously prepared R-1B two-party/future-rights agreement is **not required to complete this project filing-evidence task** and must not be presented to the Owner as a mandatory signature step. It is retained only as optional external legal hardening. A future registry/expert clarification or external-counsel review may still recommend a separate instrument for later human-authored copyrightable contributions.

Issue: `#57`. Current record: `docs/APL_IP_001_V0_2_9_SIGNOFF.md`.

## P6 — Russian Software Register sovereign lifecycle — BLOCKED / PHYSICAL INFRASTRUCTURE

APL-REG-001B repository tooling exists, but filing-grade physical proof remains open.

Required real chain:

`Russian authoritative source -> Russian-controlled source/object storage -> Russian build/compilation host -> governed/offline inputs -> exact artifacts -> Russian authoritative release/distribution storage -> evidence bundle`.

Do not claim GitVerse or another provider is compliant merely because it is Russian. GitHub remains useful for development/public distribution but does not substitute for the required physical lifecycle facts.

Issue: `#55`.

## P7 — Windows public trust / APL-REL-016 — READY FOR OWNER REVIEW

Issue: `#30`. Current review PR: `#103`.

- **DONE / PREPARATION** — PR #103 supersedes stale PR #81 and refreshes the packet from v0.2.6 to immutable v0.2.9; the first eligible embedded-signing/public-trust version is 0.2.10+.
- **DONE / FOCUSED VALIDATION** — PR records 19 public-trust/AuthentiCode-foundation tests and 29 release/evidence/repository tests passing; current head also reports the mirror check green.
- **PRESERVED BOUNDARY** — SmartScreen/App Reputation, Smart App Control/Application Control, managed-enterprise trust and Russian detached CryptoPro/Rutoken release evidence remain distinct.
- **OWNER GATE** — review/merge of the decision packet and any provider/certificate spend, key-custody commitment, production signing or release decision remain Owner-reserved.

Until Owner review, automation should maintain factual freshness only; it must not recreate the same decision packet or infer approval.

## P8 — per-application routing — READY FOR OWNER DECISION

Open decision PR: `#68`.

The packet recommends, but does not approve, an Arvectum-owned WFP ALE callout + privileged service + local proxy path.

Remaining gate:

1. refresh assumptions against current `v0.2.9` ownership/recovery baseline if necessary;
2. Owner/Product Owner selects or rejects the production architecture;
3. only after approval implement the privileged enforcement slice;
4. require real Windows host recovery/security acceptance;
5. release only as a new version.

No developer/test-signing workaround is a production substitute.

## P9 — macOS production distribution — DEFERRED

APL-MAC engineering/acceptance baseline exists. Remaining production-specific work:

- Apple production identity signing/notarization;
- Apple-specific hardened build-input path where needed;
- promoted distribution policy.

This remains deferred under the Russia-first priority model.

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

## P11 — later mobile stages

### APL-MOB-002 Android — ACTIVE

Current active implementation/physical gate is tracked in P4 / draft PR #105. After the current 0.1.7 UX/branding regression gate, continue only admitted APL-MOB-002 scope such as continuous failover/health behavior without degrading the simple one-button UX.

### iOS — DEFERRED

After Android product semantics are stable and the Apple entitlement/distribution path is explicit:

- iOS Packet Tunnel / Network Extension stage;
- common profile/routing model where platform APIs permit;
- per-app behavior only where the platform/distribution model truly supports it.

## Maintenance / repository hygiene

- PR #80 — release-evidence workflow maintenance; reconcile with current `main` before merge.
- PR #81 — superseded APL-REL-016 v0.2.6-era review branch; current trust packet is PR #103.
- PRs #90/#91/#92 — superseded Windows rollback implementations; merged PR #93/#94 and public `v0.2.9` are authoritative.
- PRs #70/#74/#82 — superseded RED OS preparation paths; merged PR #83 is authoritative.

These stale PRs are not product tracks and must not be resumed without reconciliation.

## Current execution view

- **DONE:** APL-MOB-001 Android dogfood baseline (#53/#104).
- **HUMAN IN PROGRESS:** APL-MOB-002 0.1.7 physical UX/branding/network-regression gate (#105).
- **DONE FOR CURRENT FILING EVIDENCE:** APL-IP-001 v0.2.9 provenance/right-chain packet; optional legal hardening remains non-blocking.
- **OWNER REVIEW:** APL-REL-016 current v0.2.9 trust packet (#103); PR #81 is superseded.
- **HUMAN BLOCKED:** sovereign lifecycle physical proof (#55).
- **OWNER READY / SAFE PREP AVAILABLE:** per-app routing architecture decision (#68); automation may refresh the decision material against v0.2.9 but must not choose the architecture.
- **HUMAN HOLD:** registry private evidence + external submission.
- **DEFERRED:** macOS production distribution and iOS.

The hourly watchdog should not recreate completed APL-REL-016 preparation. With the higher-priority mobile/registry tracks human-gated, the next useful safe repository-preparation lane is refreshing PR #68 against the current v0.2.9 ownership/recovery baseline, stopping at the Owner architecture gate.

## Completion discipline

Do not relabel CI as physical-host/device evidence, repository documentation as legal/corporate proof, detached Russian evidence as Microsoft native publisher trust, or automation as Owner/HUMAN approval. Published releases are immutable evidence objects; changed product bytes require a new version.
