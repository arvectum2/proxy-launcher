# Arvectum Proxy Launcher — remaining local / human / infrastructure backlog

Updated: 2026-09-13  
Canonical GitHub repository: `arvectum2/proxy-launcher`

This file contains work that cannot be truthfully completed by hosted repository automation alone, plus the remaining local/human/infrastructure decisions after publication of stable Windows `v0.2.5`.

## P0 — repository migration recovery — DONE

- **DONE** — repository/history/tags restored to `arvectum2/proxy-launcher`.
- **DONE** — current operational/governance references normalized to the canonical owner while bounded historical provenance remains unchanged.
- **DONE** — exact-SHA CI/evidence rebuilt in the canonical repository.
- **DONE** — `Protect main` governance and negative merge acceptance proven.
- **DONE** — GitVerse mirror is operational for the current release line.

Repository migration is closed and is not an active blocker.

## P1 — Windows stable release `0.2.5` — DONE / PUBLISHED

- **DONE / PHYSICAL PASS** — exact `0.2.5` Setup accepted with Controlled Folder Access enabled.
- **DONE / PHYSICAL PASS** — clean reboot/autostart, PAC, local proxy and real HTTPS-through-proxy behavior accepted; legacy Python runtime absent.
- **PUBLISHED** — GitHub stable release `v0.2.5` with governed Windows Setup and portable package.
- **PUBLISHED / MIRRORED** — GitVerse independent mirror carries the same 9 canonical payloads, using lossless one-file ZIP wrappers where GitVerse rejects the original extension.
- **IMMUTABLE** — do not move `v0.2.5` or replace its published assets.

Windows release-preservation work is no longer a prerequisite for repurposing the physical stand for Astra dual boot.

## P2 — Astra Linux / Gate R8 — READY NOW / PRIMARY LOCAL TASK

Current stand: `ARVECTUM-DEMO`, x86-64 physical laptop, Windows 11 Enterprise 25H2, intended persistent state Windows 11 + Astra Linux SE 1.8 x86-64 dual boot.

Required local sequence:

1. verify Windows recovery material and current boot health are preserved;
2. disable Fast Startup/hibernation where required for safe dual boot;
3. shrink Windows `C:` and leave Astra target space unallocated;
4. install Astra Linux SE 1.8 x86-64 with manual GPT/UEFI partitioning while preserving EFI/Windows/MSR/Recovery partitions;
5. verify both Windows and Astra boot successfully;
6. collect Astra environment/preflight evidence;
7. install and exercise the promoted Debian `.deb` lane;
8. execute APL-LNX-010 real-host acceptance: GUI/runtime, NetworkManager/PolicyKit, enable/sync/disable, rollback, autostart, crash/reboot recovery, update/remove and diagnostics/privacy;
9. close Gate R8 only from real Astra-host PASS evidence.

Ubuntu CI is not a substitute for Gate R8. AppImage remains outside promoted commercial scope pending separate compliance clearance.

## P3 — human/legal clean-IP boundary — HUMAN/LEGAL PENDING

Current technical provenance/sovereignty/refactor/license work is complete. Remaining human/legal work:

1. R-1 — execute/verify author -> ООО «Арвектум» rights basis for the selected clean-IP candidate;
2. R-2 — record actual Rospatent registration/transfer status;
3. R-3 — record actual corporate/interested-transaction basis/approval/exception where applicable;
4. confirm factual provenance for the selected candidate;
5. make the explicit authorized `APPROVED`, `CONDITIONAL` or `HOLD` decision.

Only explicit `APPROVED` unlocks a governed clean-IP baseline/tag. This lane governs its own legal/IP closure and must not be rewritten as though it were an unperformed prerequisite to the already-published immutable `v0.2.5` release.

## P4 — Windows public trust / APL-REL-016 — READY NOW / PARALLEL

Open issue: `#30`.

Required investigation/decision:

1. separate SmartScreen App Reputation, Smart App Control/Application Control and enterprise managed trust;
2. confirm what native Windows public distribution requires for a future signed Win32 release;
3. investigate Russian-native CA/Минцифры/enterprise trust paths first rather than assuming GOST УКЭП is equivalent to Authenticode;
4. retain CryptoPro/Rutoken detached signing as a separate Russian release-evidence layer;
5. choose a future production trust/distribution path and acceptance matrix;
6. apply any binary-signing change only to a new release (`0.2.6+`), never by mutating `v0.2.5`.

International Microsoft/OV/EV providers remain low priority unless the chosen Windows-native trust path requires them.

## P5 — per-application routing — READY FOR ARCHITECTURE DECISION / STOP-GATE

APL-ROUTE-001/002/004 and the autonomous APL-ROUTE-003 control-plane work are retained. The prerequisite of a trustworthy Windows release baseline is now satisfied by `0.2.5`.

Before Windows native production enforcement:

1. choose the enforcement architecture deliberately;
2. define ownership, recovery and failure semantics for the native enforcement layer;
3. prove the path on a real Windows host without test-signing/developer-mode shortcuts;
4. bind capability-aware UX to the real supported platform behavior;
5. release it only as a new product version with fresh evidence.

## P6 — macOS production distribution — AVAILABLE / DEFERRED

APL-MAC-001..008 engineering and retained acceptance evidence are complete. Remaining work is production-specific:

- Apple production identity signing/notarization;
- any Apple-specific hardened build-input path;
- final promoted distribution policy.

This lane remains deferred under the Russia-first priority model and can be activated when commercial demand justifies it.

## P7 — mobile stage — FUTURE

After desktop baselines are sufficiently stable:

- build iOS application;
- build Android application;
- reuse the common routing/configuration model where platform APIs permit;
- support per-application selection/routing only where the platform actually allows it, with explicit capability UX otherwise.

## Current parallel execution order

- **[Primary local] READY NOW:** Astra dual boot -> APL-LNX-010 -> Gate R8.
- **[Human] PARALLEL:** R-1/R-2/R-3 + factual confirmation + final APL-IP-001 decision.
- **[Windows trust] PARALLEL:** APL-REL-016 investigation/architecture for `0.2.6+`.
- **[Product discovery] PARALLEL/OPTIONAL:** resolve per-application-routing Windows enforcement architecture.
- **[macOS] DEFERRED:** activate production signing/notarization when prioritized.
- **[Mobile] FUTURE:** iOS/Android after desktop baselines.

## Completion discipline

Do not relabel CI as physical-host evidence, detached Russian release evidence as Microsoft native publisher trust, or automation as human/legal approval. Preserve historical identifiers where they are part of immutable evidence. Do not mutate `v0.2.5`. Current operational repository references must use `arvectum2/proxy-launcher`.
