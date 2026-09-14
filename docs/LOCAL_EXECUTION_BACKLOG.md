# Arvectum Proxy Launcher — remaining local / human / infrastructure backlog

Updated: 2026-09-14  
Canonical GitHub repository: `arvectum2/proxy-launcher`

This file contains work that cannot be truthfully completed by hosted repository automation alone, plus the remaining local/human/infrastructure decisions after publication of stable Windows `v0.2.5`.

## P0 — repository migration recovery — DONE

- **DONE** — repository/history/tags restored to `arvectum2/proxy-launcher`.
- **DONE** — current operational/governance references normalized to the canonical owner while bounded historical provenance remains unchanged.
- **DONE** — exact-SHA CI/evidence rebuilt in the canonical repository.
- **DONE** — `Protect main` governance and negative merge acceptance proven.
- **DONE** — GitVerse mirror is operational for the current release line.
- **DONE** — stale Windows signing-chain encoding test contract fixed; Russian-first signing CI is green again.

Repository migration is closed and is not an active blocker.

## P1 — Windows stable release `0.2.5` — DONE / PUBLISHED

- **DONE / PHYSICAL PASS** — exact `0.2.5` Setup accepted with Controlled Folder Access enabled.
- **DONE / PHYSICAL PASS** — clean reboot/autostart, PAC, local proxy and real HTTPS-through-proxy behavior accepted; legacy Python runtime absent.
- **PUBLISHED** — GitHub stable release `v0.2.5` with governed Windows Setup and portable package.
- **PUBLISHED / MIRRORED** — GitVerse independent mirror carries the same canonical payload set.
- **IMMUTABLE** — do not move `v0.2.5` or replace its published assets.

## P2 — Astra Linux / Gate R8 — IN PROGRESS / PRIMARY LOCAL TASK

Current stand: `ARVECTUM-DEMO`, x86-64 physical laptop, Windows 11 Enterprise 25H2 + Astra Linux SE 1.8 x86-64 dual-boot acceptance path.

Active implementation/fix PR: `#62`, branch `fix/apl-lnx-010-r8-astra`.

Real-host acceptance exposed two product defects in the Linux candidate: mutable runtime/state resolving into the root-owned install directory, and Windows-specific active/recovery UX copy. PR #62 fixes both and adds focused regression tests. The deterministic suite is **802/802 PASS**.

Physical acceptance progress on final candidate source `d18cf396b8e324da070bd21a0ae14598df7d394f`, `.deb` SHA-256 `d8b119f622961360ef08ac39bede6ff221b54f67ee9a37b19711a5d6774d1588`:

- strict preflight/baseline, package install, GUI Linux/Astra validation and real enable — PASS;
- Phase 4 no-proxy UI sync/restoration — PASS;
- Phase 5 GUI disable exact rollback comparator — PASS;
- Phase 6 XDG per-user autostart setup/network preservation — PASS so far; login proof is combined with Phase 8;
- Phase 7 SIGKILL crash/relaunch recovery + exact comparator — PASS;
- **current checkpoint: Phase 8 reboot/login recovery**.

Remaining local sequence:

1. complete Phase 8 reboot/login recovery on the exact final candidate;
2. complete Phase 9 update/remove/reinstall state preservation;
3. complete Phase 10 diagnostics privacy and final cleanup;
4. produce host attestation and `SUMMARY.md`;
5. run `qa/verify_astra_acceptance_bundle.py` to `APL-LNX-010 VERDICT: EVIDENCE COMPLETE`;
6. preserve the same run with enough machine-readable/raw evidence to serve as the first APL-REG-001C trusted-OS acceptance record;
7. reconcile/merge PR #62 with current `main` under required review/CI rules;
8. close Gate R8 only from complete real Astra-host PASS evidence.

Ubuntu CI is not a substitute for Gate R8. AppImage remains outside promoted commercial scope pending separate compliance clearance.

## P3 — РЕД ОС / second registry OS acceptance — READY AFTER ASTRA GATE R8

APL-REG-001C is paused until two real-host acceptance records exist. Working pair: Astra Linux Special Edition + РЕД ОС.

For РЕД ОС:

1. re-verify qualifying trusted-software status and different-rightsholder condition at execution time;
2. prepare a real host/VM only if the applicable requirement permits the chosen evidence form; prefer a real-host acceptance path consistent with the registry contract;
3. identify exact OS edition/version/build and Proxy Launcher commit/package SHA-256;
4. run clean install, application start/stop, proxy routing/no-proxy, restart/recovery/autostart where applicable, diagnostics/logging, uninstall/removal and post-state;
5. retain dated human acceptance plus raw/machine-readable evidence;
6. only after both Astra + РЕД ОС records exist, resume compatibility reconciliation and registry protocol generation.

Generic Linux CI is not a substitute for these two OS acceptance runs.

## P4 — Android APL-MOB-001 physical dogfood — READY NOW

Draft PR: `#53`, branch `apl-mob-001-android-spike`.

Repository/CI already provides a native Android project, a real `VpnService`/TUN slice and a debug APK artifact. Remaining local gate:

1. install the current debug APK on a physical Android phone;
2. verify public IP changes through a real SOCKS5 proxy;
3. verify the real HTTP proxy used by desktop Proxy Launcher;
4. test wrong credentials and proxy outage;
5. test browser plus ordinary apps;
6. test sleep/wake;
7. test Wi-Fi -> cellular -> Wi-Fi transitions;
8. compare latency/throughput against direct and selected reference clients;
9. inspect device logs/files for credential leakage;
10. only after physical evidence decide reconnect/Always-on behavior and whether PR #53 is ready to leave draft/merge.

## P5 — human/legal clean-IP boundary — HUMAN/LEGAL PENDING / EXECUTION-READY

Exact `v0.2.5` engineering provenance/SBOM reconciliation is complete. A private rights instrument dated 2026-09-14 has been recorded by governed digests and factual-effect metadata without publishing private material. The canonical sign-off remains **NOT APPROVED**.

Remaining human/legal work:

1. R-1 — inspect the executed rights instrument(s) and conclude whether the necessary exclusive rights are held by ООО «Арвектум» for the exact object/scope;
2. R-2 — confirm factual Rospatent status if relied upon; current repository record states the program is not yet registered and does not rely on Rospatent as the transfer basis;
3. R-3 — review applicable corporate approval/interested-transaction/exception basis;
4. R-4 — explicitly carry forward human authorship/control facts to the exact v0.2.5 changes and selected release scope;
5. review promoted Windows distribution scope against THIRD_PARTY evidence;
6. make the explicit authorized `APPROVED` or `REJECTED / REMEDIATION REQUIRED` decision.

Only explicit `APPROVED` unlocks a governed clean-IP baseline/tag. Never move the immutable `v0.2.5` tag.

## P6 — Russian Software Register sovereign lifecycle — PHYSICAL INFRASTRUCTURE GATE

APL-REG-001B repository tooling is complete; proof of real infrastructure is not.

When infrastructure is available, prove the target chain:

`Russian authoritative source -> Russian-controlled build host -> offline governed inputs -> exact artifacts -> Russian authoritative artifact/distribution storage -> release evidence bundle`.

Do not claim GitVerse or any provider is compliant merely because it is Russian. GitHub/GitHub Actions/GitHub Releases remain useful development/secondary channels but are not filing-grade sovereign evidence by themselves.

## P7 — Windows public trust / APL-REL-016 — READY NOW / PARALLEL

Open issue: `#30`.

Required investigation/decision:

1. separate SmartScreen App Reputation, Smart App Control/Application Control and enterprise managed trust;
2. confirm what native Windows public distribution requires for a future signed Win32 release;
3. investigate Russian-native CA/Минцифры/enterprise trust paths first rather than assuming GOST УКЭП is equivalent to Authenticode;
4. retain CryptoPro/Rutoken detached signing as a separate Russian release-evidence layer;
5. choose a future production trust/distribution path and acceptance matrix;
6. apply any binary-signing change only to a new release (`0.2.6+`), never by mutating `v0.2.5`.

International Microsoft/OV/EV providers remain low priority unless the chosen Windows-native trust path requires them.

## P8 — per-application routing — READY FOR ARCHITECTURE DECISION / STOP-GATE

APL-ROUTE-001/002/004 and the autonomous APL-ROUTE-003 control-plane work are retained. The trustworthy Windows release prerequisite is satisfied by `0.2.5`.

Before Windows native production enforcement:

1. choose the enforcement architecture deliberately;
2. define ownership, recovery and failure semantics for the native enforcement layer;
3. prove the path on a real Windows host without test-signing/developer-mode shortcuts;
4. bind capability-aware UX to the real supported platform behavior;
5. release it only as a new product version with fresh evidence.

## P9 — macOS production distribution — AVAILABLE / DEFERRED

APL-MAC-001..008 engineering and retained acceptance evidence are complete. Remaining work is production-specific:

- Apple production identity signing/notarization;
- Apple-specific hardened build-input path where needed;
- final promoted distribution policy.

This lane remains deferred under the Russia-first priority model and can be activated when commercial demand justifies it.

## P10 — registry documentation/submission — PAUSED BEHIND TWO-OS GATE

After Astra Linux SE + РЕД ОС acceptance and compatibility reconciliation:

- APL-REG-001D — frozen Russian registry documentation pack;
- APL-REG-001E — private corporate evidence pack outside the public repository;
- APL-REG-001F — current-law/classifier/release-byte/rights/infrastructure pre-submission audit;
- external electronic submission with authorized УКЭП.

## P11 — iOS / later mobile stage — FUTURE

After Android dogfood and sufficiently stable desktop/mobile product semantics:

- build iOS application;
- reuse the common routing/configuration model where platform APIs permit;
- support per-application selection/routing only where the platform actually allows it;
- add APL-MOB-002 proxy pool/health checks/automatic failover after MVP semantics are proven.

## Current parallel execution order

- **[Primary local] IN PROGRESS:** Astra APL-LNX-010 physical acceptance -> finish Phase 8/9/10 -> verifier -> Gate R8 + first APL-REG-001C OS record.
- **[Mobile local] READY NOW:** physical Android dogfood for PR #53.
- **[Human] READY NOW:** final APL-IP-001 R-1..R-4 review and decision.
- **[Windows trust] PARALLEL:** APL-REL-016 architecture for `0.2.6+`.
- **[Registry infrastructure] PARALLEL WHEN AVAILABLE:** APL-REG-001B physical sovereign lifecycle proof.
- **[Product discovery] PARALLEL/OPTIONAL:** resolve per-application-routing Windows enforcement architecture.
- **[Second Linux OS] NEXT AFTER R8:** РЕД ОС real-host acceptance to unlock APL-REG-001C continuation.
- **[macOS] DEFERRED:** production signing/notarization when prioritized.
- **[iOS] FUTURE:** after Android dogfood and desktop stability.

## Completion discipline

Do not relabel CI as physical-host/device evidence, detached Russian release evidence as Microsoft native publisher trust, or automation as human/legal approval. Preserve historical identifiers where they are part of immutable evidence. Do not mutate `v0.2.5`. Current operational repository references must use `arvectum2/proxy-launcher`.
