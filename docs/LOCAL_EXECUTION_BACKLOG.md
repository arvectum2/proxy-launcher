# Arvectum Proxy Launcher — remaining local / human / infrastructure backlog

Updated: 2026-09-19  
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Current stable release: `v0.2.10`

This file contains the remaining work that cannot be truthfully completed by hosted repository automation alone, plus active review/owner gates after the Windows/Astra/RED OS desktop baseline and registry dossier work.

## P0 — repository / executor baseline — DONE

- **DONE** — canonical repository is `arvectum2/proxy-launcher`; migration recovery and main-protection acceptance are historical closure.
- **DONE** — the single hourly `Proxy Launcher Watchdog` is enabled and reads `.agent/executor-policy.yaml`, `.agent/execution-queue.yaml`, `.agent/current-task.yaml`, this backlog and the canonical roadmap.
- **RULE** — watchdog may skip blocked HUMAN/OWNER gates to do later independent admitted preparation, but may not reorder the queue or invent scope/approval.

## P1 — current stable release `v0.2.10` — PUBLISHED

Published 2026-09-19:

- Windows x64 Setup;
- Windows x64 portable ZIP;
- Astra Linux x86-64 DEB;
- RED OS 8.0.3 x86-64 RPM;
- generic Linux x86-64 AppImage;
- `SHA256SUMS.txt`.

`v0.2.10` is the current immutable desktop release. It retains the v0.2.9 rollback-ownership safety contract and promotes the governed AppImage lane into the public stable release set. Stable macOS distribution remains excluded pending deliberate Apple production signing/notarization; separate `v0.2.10-macos-test.1` arm64 prerelease exists for dogfood only.

Historical progression retained for provenance:

- `v0.2.5` — Windows CFA-safe physically accepted baseline;
- `v0.2.6` — Windows + Astra release lane;
- `v0.2.7` — RED OS release track;
- `v0.2.8` — Linux mixed-state recovery hardening;
- `v0.2.9` — Windows saved-or-Arvectum recovery symmetry;
- `v0.2.10` — promoted AppImage + current desktop packaging baseline.

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

## P4 — Android mobile track — MOB-001/MOB-002/MOB-003 DONE, MOB-004 PLANNED

### APL-MOB-001 — DONE

- PR #53 established the physically accepted VpnService/TUN transport baseline.
- PR #104 added the physically accepted multiprofile baseline.

### APL-MOB-002 — DONE / PUBLIC ANDROID 0.1.17

- **MERGED / PHYSICAL** — PR #119 completed continuous Auto health/failover and physical-network handoff.
- **PUBLIC** — `android-v0.1.17` is published from merge commit `8b07165a2f8404ed711399c6e65ec76a22b46a72`.
- **PASS** — physical acceptance covers Wi-Fi → hotspot → Wi-Fi handoff and automatic proxy failover without manual OFF/ON.
- **MIRRORED** — GitVerse parity is recorded by the completed release track.

### APL-MOB-003 — DONE / PHYSICAL PASS / INTEGRATED

Accepted implementation: Android dogfood `0.1.19`; original PR `#125` is superseded and integration PR `#130` is merged.

Completed evidence:
- site/domain/URL/IP exclusions are implemented in the existing proxy popup; no per-application chooser was added;
- Owner reported the myip.com exclusion working on device;
- clarified explicit input + **Add** button + per-entry row/remove UX was accepted;
- Android CI run `35435184809` succeeded after the compile fix and mobile-branch workflow trigger update;
- accepted 0.1.19 APK SHA-256: `c5940b1e494df5de82d84493182f83fcbe75182fe261f372a1269a94ba880c71`.

The implementation/physical task is complete and rebased integration PR #130 merged to `main` as `c645825ec8b3fd142e0b6b7eca3c1fc8f6261550`. A public Android 0.1.19 release is still a separate action; do not represent 0.1.19 as publicly released unless that release exists.

### APL-MOB-004 — PLANNED / OWNER PRIORITY + PACKAGE-IDENTITY GATE

Roadmap only; no ad SDK/private distribution implementation exists yet. MOB-003 is complete and integrated. Implementation should start only after the Owner explicitly prioritizes monetization and decides the private package/update identity.

- public channel: ads-enabled Android artifacts for GitHub, GitVerse, Arvectum site and RuStore;
- initial target: Yandex Mobile Ads / App Open with first-launch grace, frequency limiting, fail-open behavior and privacy/consent documentation;
- private channel: no-ads artifact from the same codebase, preferably via Gradle flavor/build configuration;
- private artifact must live outside the public GitHub release surface; retain immutable private APKs/hashes plus a stable latest APK on the Mac mini;
- before implementation, Owner must decide private package identity/update semantics so public/RuStore updates cannot unexpectedly replace the private build.

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

## P7 — Windows public trust / APL-REL-016 — READY FOR OWNER REVIEW

Issue: `#30`. Current review PR: `#132`.

- **DONE / REVIEW PREPARATION** — PR #132 supersedes #103 and refreshes the packet to current immutable `v0.2.10`; the first eligible future embedded-signing/public-trust release is `v0.2.11+`.
- **DONE / RECHECK** — current Microsoft public-trust geography, CA/B Forum code-signing requirements and trust-layer boundaries were rechecked for the packet.
- **DONE / EXACT-HEAD CI** — all observed checks are green, including REL-016 contract tests, PowerShell syntax, signed-app → portable → installer smoke, controlled-offline-build, required build and installer.
- **OWNER GATE** — review/merge of #132 and any provider/certificate spend, key-custody commitment, production signing or release decision remain Owner-reserved.

Automation may maintain factual freshness, but must not infer approval or merge the REVIEW packet automatically.

## P8 — per-application routing — READY FOR OWNER DECISION

Open decision PR: `#68`.

The packet recommends, but does not approve, an Arvectum-owned WFP ALE callout + privileged service + local proxy path.

Remaining gate:

1. refresh assumptions against current `v0.2.10` ownership/recovery baseline if necessary;
2. Owner/Product Owner selects or rejects the production architecture;
3. only after approval implement the privileged enforcement slice;
4. require real Windows host recovery/security acceptance;
5. release only as a new version.

No developer/test-signing workaround is a production substitute.

## P9 — macOS production distribution — TEST LANE EXISTS / PRODUCTION DEFERRED

APL-MAC engineering/acceptance baseline exists. Separate arm64 prerelease `v0.2.10-macos-test.1` has been published for dogfood with checksum/mirror evidence; this is not the stable production macOS channel.

Remaining production-specific work:
- Apple Developer ID production identity signing/notarization;
- Apple-specific hardened build-input path where needed;
- promoted stable distribution policy.

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

### APL-MOB-004 Android monetization/distribution — PLANNED

Tracked after the current APL-MOB-003 physical gate. Implementation requires explicit Owner prioritization and package/update-identity decision; no ad SDK or private release infrastructure has been added yet.

### iOS — DEFERRED

After Android product semantics are stable and the Apple entitlement/distribution path is explicit:

- iOS Packet Tunnel / Network Extension stage;
- common profile/routing model where platform APIs permit;
- per-app behavior only where the platform/distribution model truly supports it.

## Maintenance / repository hygiene

- PR #80 — release-evidence workflow maintenance; reconcile with current `main` before merge.
- PR #81 — superseded APL-REL-016 v0.2.6-era review branch; current trust packet is PR #103.
- PR #113 — redundant AppImage closeout branch overtaken by merged PR #112.
- PR #117 — redundant Android 0.1.13 closeout overtaken by merged PR #118.
- PR #120 — superseded continuous-failover development branch overtaken by merged PR #119.
- PR #124 — stale APL-MOB-002 closeout branch; canonical active Android task is APL-MOB-003 / PR #125.
- PRs #90/#91/#92 — superseded Windows rollback implementations; merged PR #93/#94 and public `v0.2.9` are authoritative.
- PRs #70/#74/#82 — superseded RED OS preparation paths; merged PR #83 is authoritative.

These stale PRs are not product tracks and must not be resumed without reconciliation.

## Current execution view

- **DESKTOP STABLE:** v0.2.10 is public with Windows Setup/portable, Astra DEB, RED OS RPM and Linux AppImage.
- **DONE:** APL-MOB-001 and APL-MOB-002; public Android baseline is 0.1.17.
- **DONE / INTEGRATED:** APL-MOB-003 Android site exclusions, accepted 0.1.19 implementation merged via PR #130; public 0.1.19 release remains separate.
- **PLANNED / OWNER-GATED:** APL-MOB-004 Android public-ads + private-no-ads dual distribution; waiting on explicit priority and package/update identity.
- **DONE FOR CURRENT FILING EVIDENCE:** APL-IP-001 v0.2.9 provenance/right-chain packet; optional legal hardening remains non-blocking.
- **OWNER REVIEW:** APL-REL-016 PR #132 is current, exact-head CI is green, and no provider/signing/release action is implied.
- **HUMAN BLOCKED:** sovereign lifecycle physical proof (#55).
- **OWNER READY:** per-app routing architecture decision (#68); refresh against v0.2.10 if needed, but do not choose the architecture automatically.
- **HUMAN HOLD:** registry private evidence + external submission.
- **MAC:** test prerelease exists; production Apple signing/notarization remains deferred.
- **DEFERRED:** iOS.

APL-MOB-003 is complete/integrated and APL-MOB-004 is Owner-gated. APL-REL-016 is already at the Owner-review boundary in PR #132. The next useful safe autonomous preparation lane is therefore PR #68 against v0.2.10, stopping before the Owner architecture decision.

## Completion discipline

Do not relabel CI as physical-host/device evidence, repository documentation as legal/corporate proof, detached Russian evidence as Microsoft native publisher trust, or automation as Owner/HUMAN approval. Published releases are immutable evidence objects; changed product bytes require a new version.
