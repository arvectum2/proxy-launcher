# Arvectum Proxy Launcher — remaining local / human / infrastructure backlog

Updated: 2026-09-10  
Canonical GitHub repository: `arvectum2/proxy-launcher`

This file contains work that cannot be truthfully completed by hosted repository automation alone, plus immediate repository/admin prerequisites for those gates.

## P0 — repository migration recovery — CURRENT

### P0.1 — canonical repository content

- **DONE** — repository/history/tags restored to `arvectum2/proxy-launcher`.
- **DONE** — GitVerse mirror workflow is compatible with the new GitHub owner because it resolves `${{ github.repository }}` dynamically.
- **CURRENT** — normalize current operational/governance references and enforce a bounded repository-identity hygiene guard.
- **CURRENT** — rebuild Windows/SAST/provenance/release-evidence CI on one exact post-migration `main` SHA in the new GitHub repository.
- **CURRENT** — require GitVerse mirror PASS for that same exact SHA.

Old GitHub Actions runs are not treated as current-repository release evidence. Historical commits/tags/evidence remain valid provenance and must not be rewritten.

### P0.2 — GitHub `main` protection — ADMIN PENDING

Observed on 2026-09-10 for the new canonical repository:

- `main.protected = false`;
- protection disabled;
- required status-check enforcement off;
- no required checks configured.

Owner/admin must restore the governed contract documented in `docs/GITHUB_MAIN_PROTECTION_RECOVERY.md`, then perform a negative acceptance test proving a normal merge is rejected while required `build` is still pending.

Do not treat migration recovery as complete until this passes.

## P1 — ARVECTUM-DEMO Windows physical stand — CURRENT

Current stand: x86-64 physical laptop, Windows 11 Enterprise 25H2, intended permanent state Windows 11 + Astra Linux SE 1.8 x86-64 dual boot.

### P1.1 — APL-WIN-014 App Control for Business

Status: **WEB/ENGINEERING PREPARATION COMPLETE / REAL-HOST FINAL EVIDENCE PENDING**.

Use `docs/APL_WIN_014_LOCAL_GATE.md`.

Exact retained predecessor remains:

- commit `0ea08d9c815da36d0175f62db153de78f89731fc`;
- path `release/Arvectum-Proxy-Launcher-Windows-0.2.2-P0.4-client.zip`;
- Git blob SHA-1 `574d3dc5f90a116555e3a72ff3288c31c19d3dc7`;
- blob size `15963815`;
- application SHA-256 `7EF02652E31BBBD68833BE599135CF59519C42B1F8A8FEBB580B3891FFC35EC0`.

Required local sequence:

1. materialize the exact P0.4 package with `tools/windows_app_control_recover_0_2_2_baseline.ps1`;
2. generate current `0.2.3` and historical P0.4 trust packs against the same enforced base policy;
3. deploy both supplemental policies through the approved App Control management path;
4. execute `tools/windows_app_control_local_gate_complete.ps1`;
5. require exact-current enforced PASS plus real `0.2.2 P0.4 -> 0.2.3` cross-version PASS;
6. preserve any genuine Code Integrity denial as BLOCK evidence rather than weakening policy;
7. export and hash-verify final evidence outside the stand.

Same-version repair is not cross-version evidence.

### P1.2 — APL-REL-014 exact signed-set lifecycle — PARTIAL / READY

Real installer transition/uninstall/fresh-reinstall behavior was previously proven after #172. Complete/export any remaining exact signed-set lifecycle/recovery evidence before repartitioning the machine for Astra.

### P1.3 — clean-machine endpoint-denied rebuild — DEFERRED

Do not reinstall the current stand merely to recreate a pristine environment. Keep this resilience drill for a naturally suitable future machine/environment.

## P2 — human/legal clean-IP boundary — HUMAN/LEGAL PENDING

Current decision record: `docs/APL_IP_001_POST_172_SIGNOFF.md`.

The selected technical candidate remains identified by its immutable commit/tree; repository migration does not move that candidate.

Remaining human/legal work:

1. R-1 — execute/verify author → ООО «Арвектум» rights basis covering the selected candidate;
2. R-2 — record actual Rospatent registration/transfer status;
3. R-3 — record actual corporate/interested-transaction basis/approval/exception where applicable;
4. confirm factual provenance for the selected candidate;
5. make the explicit authorized `APPROVED`, `CONDITIONAL` or `HOLD` decision.

Only explicit `APPROVED` unlocks a governed clean-IP tag. Material product/build/package implementation changes require a new exact candidate reconciliation.

## P3 — next stable production release — READY AFTER REPOSITORY + REQUIRED GATES

The current product line remains `0.2.3`, but the historical `v0.2.3` tag is immutable and does not point to the post-migration tree. Do not move or recycle it.

For the first new stable release from `arvectum2`:

1. restore branch protection;
2. select a new SemVer version (natural patch candidate: `0.2.4` if scope remains release/migration hardening only);
3. make the version bump as a governed candidate change;
4. obtain required exact-SHA green Windows portable/installer, SAST and Release Evidence Package runs in `arvectum2`;
5. build exact final assets;
6. add REL-012 verifier UX before signing;
7. run REL-011 with physical Rutoken/CryptoPro;
8. run REL-013 and require `Publication decision: PUBLISH`;
9. publish only that exact verified set and preserve external gate evidence.

Current company УКЭП remains `RELEASE-EVIDENCE-ONLY`; embedded Authenticode/SmartScreen/ОТУЦ trust must not be claimed.

## P4 — Astra Linux / Gate R8 — READY AFTER WINDOWS-ONLY GATES

On ARVECTUM-DEMO:

1. finish/export Windows-only evidence;
2. preserve recovery material and disable Fast Startup/hibernation as applicable;
3. shrink Windows `C:` and leave Astra space unallocated;
4. install Astra Linux SE 1.8 x86-64 with manual GPT/UEFI partitioning, preserving EFI/Windows/MSR/Recovery partitions;
5. verify both OSes boot;
6. collect Astra preflight;
7. execute APL-LNX-010 real `.deb` acceptance including GUI/runtime, NetworkManager/PolicyKit, enable/sync/disable, rollback, autostart, crash/reboot recovery, update/remove and diagnostics/privacy;
8. close Gate R8 only from real Astra-host PASS evidence.

Ubuntu CI is not a substitute. Debian `.deb` remains the promoted Linux/Astra lane; AppImage remains outside promoted commercial scope pending separate downstream compliance clearance.

## P5 — per-application routing — READY / STOP-GATE

APL-ROUTE-001/002/004 and the autonomous control-plane work are retained. Before Windows native production enforcement, choose an accepted enforcement architecture deliberately. Do not use test-signing/developer modes as a production workaround.

This is the product-next-stage track after repository/release baseline closure, not part of migration recovery.

## Current parallel execution order

- **[Web/GitHub] CURRENT:** finish migration reconciliation and exact-SHA CI/mirror re-baseline.
- **[Admin] CURRENT:** restore `main` protection and prove required-check enforcement with a negative merge test.
- **[Win] CURRENT:** APL-WIN-014 real App Control gate, then remaining APL-REL-014 evidence.
- **[Human] PARALLEL:** R-1/R-2/R-3 + factual confirmation + final APL-IP-001 decision.
- **[Linux] AFTER WINDOWS:** Astra dual boot -> APL-LNX-010 -> Gate R8.
- **[Product] AFTER BASELINE:** resolve the per-application-routing Windows enforcement STOP-GATE.

## Completion discipline

Do not relabel migrated history as new-repository CI evidence, CI as physical-host evidence, or automation as human/legal approval. Preserve historical identifiers where they are part of immutable evidence, but use `arvectum2/proxy-launcher` for every current operational repository reference.
