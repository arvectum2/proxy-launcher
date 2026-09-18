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

## P4 — Android APL-MOB-001 physical dogfood — READY NOW / HUMAN

Draft PR: `#53`, branch `apl-mob-001-android-spike`.

Repository/CI provides a native Android project, real `VpnService`/TUN path, secure profile storage and a debug APK. Remaining physical gate:

1. install the current APK on a real Android phone;
2. verify public IP through a real SOCKS5 proxy;
3. verify the real HTTP proxy used by desktop Proxy Launcher;
4. test wrong credentials and proxy outage;
5. test browser plus ordinary apps;
6. test sleep/wake;
7. test Wi-Fi → cellular → Wi-Fi;
8. compare latency/throughput against direct/reference clients;
9. inspect logs/files for credential leakage;
10. only then decide reconnect/Always-on behavior and whether PR #53 may leave draft.

## P5 — IP / corporate rights boundary — BLOCKED / OWNER-HUMAN

Current final object: exact public `v0.2.9`.

Repository engineering is reconciled: exact source/tag tree, promoted package digests, provenance and CycloneDX SBOM are governed; the v0.2.5 -> v0.2.9 material drift is classified. Historical v0.2.5 remains an immutable provenance/physical-acceptance anchor.

The executed 2026-09-14 private decision remains the base rights-chain evidence. **Do not re-execute it merely because the release version changed.** Remaining human/private findings are:

1. inspect the actual 2026-09-14 instrument and verify the base Arvectum Proxy Launcher rights transfer (R-1A);
2. establish the actual rights basis for material creative contributions after 2026-09-14 included in v0.2.9 (R-1B) — existing future-results wording, service/employment basis, separate assignment or another real documented basis;
3. confirm current Rospatent factual status (R-2);
4. confirm applicable corporate approval/exception and current Russian-control facts (R-3);
5. explicitly carry forward human creative/architectural control and no-known-deliberate-copying facts to v0.2.9 (R-4);
6. select the promoted approval scope (Windows Setup/portable, Astra DEB, RED OS RPM; AppImage remains excluded);
7. make an explicit authorized `APPROVED` or remediation decision.

Issue: `#57`. Current sign-off: `docs/APL_IP_001_V0_2_9_SIGNOFF.md`.
## P6 — Russian Software Register sovereign lifecycle — BLOCKED / PHYSICAL INFRASTRUCTURE

APL-REG-001B repository tooling exists, but filing-grade physical proof remains open.

Required real chain:

`Russian authoritative source -> Russian-controlled source/object storage -> Russian build/compilation host -> governed/offline inputs -> exact artifacts -> Russian authoritative release/distribution storage -> evidence bundle`.

Do not claim GitVerse or another provider is compliant merely because it is Russian. GitHub remains useful for development/public distribution but does not substitute for the required physical lifecycle facts.

Issue: `#55`.

## P7 — Windows public trust / APL-REL-016 — READY NOW / REVIEW

Issue: `#30`. Active review PR: `#81`.

Current action:

1. refresh PR #81 from its `v0.2.6` baseline to current `v0.2.9`;
2. re-verify current SmartScreen/App Reputation, Smart App Control/Application Control and managed-enterprise boundaries;
3. keep Russian detached CryptoPro/Rutoken evidence separate from native Windows publisher trust;
4. keep Russian-native paths first where they can actually satisfy the chosen trust model;
5. stop before provider/certificate purchase, key-custody commitment, production signing or release.

Final provider/distribution/signing architecture remains an Owner gate.

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

## P11 — iOS / APL-MOB-002 — DEFERRED

After Android dogfood establishes stable mobile semantics:

- iOS Packet Tunnel / Network Extension stage;
- common profile/routing model where platform APIs permit;
- APL-MOB-002 proxy pool, health checks and automatic failover;
- per-app behavior only where the platform/distribution model truly supports it.

## Maintenance / repository hygiene

- PR #80 — release-evidence workflow maintenance; reconcile with current `main` before merge.
- PRs #90/#91/#92 — superseded Windows rollback implementations; merged PR #93/#94 and public `v0.2.9` are authoritative.
- PRs #70/#74/#82 — superseded RED OS preparation paths; merged PR #83 is authoritative.

These stale PRs are not product tracks and must not be resumed without reconciliation.

## Current execution view

- **HUMAN READY:** Android physical dogfood (#53).
- **OWNER/HUMAN BLOCKED:** final IP/corporate rights disposition (#57).
- **REVIEW READY:** APL-REL-016 trust packet refresh to v0.2.9 (#81).
- **HUMAN BLOCKED:** sovereign lifecycle physical proof (#55).
- **OWNER READY:** per-app routing architecture decision (#68).
- **HUMAN HOLD:** registry private evidence + external submission.
- **DEFERRED:** macOS production distribution, then iOS/APL-MOB-002.

The hourly watchdog should therefore skip the earlier HUMAN/OWNER blockers and use APL-REL-016 as the first useful autonomous review-preparation lane unless a higher-priority physical/human task becomes actively claimed.

## Completion discipline

Do not relabel CI as physical-host/device evidence, repository documentation as legal/corporate proof, detached Russian evidence as Microsoft native publisher trust, or automation as Owner/HUMAN approval. Published releases are immutable evidence objects; changed product bytes require a new version.
