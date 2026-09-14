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

## P2 — Astra Linux / Gate R8 — DONE / PHYSICAL PASS

Physical acceptance stand: x86-64 HP EliteBook 735 G6 running Astra Linux Special Edition 1.8.1 / Fly / X11 on a non-virtualized host.

Final accepted `0.2.5` candidate source: `d18cf396b8e324da070bd21a0ae14598df7d394f`; `.deb` SHA-256: `d8b119f622961360ef08ac39bede6ff221b54f67ee9a37b19711a5d6774d1588`.

Gate R8 closure:

- **PASS** — strict Astra physical-host preflight, package install and GUI/Linux-Astra UX;
- **PASS** — real NetworkManager enable and normal disable with exact rollback comparator;
- **PASS** — no-proxy synchronization while preserving the durable captured baseline;
- **PASS** — XDG per-user autostart/login behavior;
- **PASS** — SIGKILL crash/relaunch recovery with exact rollback comparator;
- **PASS** — real reboot/login recovery with pending rollback surviving reboot and exact post-recovery comparator;
- **PASS** — reinstall/remove/reinstall lifecycle with user-state preservation;
- **PASS** — diagnostics/support privacy and final cleanup; no pending rollback remains;
- **PASS** — `HOST_ATTESTATION.env`, `SUMMARY.md` and `qa/verify_astra_acceptance_bundle.py` (`APL-LNX-010 VERDICT: EVIDENCE COMPLETE`);
- **MERGED** — R8 fixes in PR `#62`, main merge commit `cb8655278bcb0899104bb5e4161c4de0497b6226`;
- **CI PASS** — exact PR head `e0012b2d196f75cc3329e0bddec0a655387145a9` passed all 16 reported GitHub Actions workflows, including Windows P0 portable and Windows installer.

Real-host acceptance exposed and closed Linux per-user state-path, Linux/Astra status-copy, diagnostics home-path privacy and cross-platform regression-test portability defects. Ubuntu CI was not used as a substitute for the physical Gate R8 evidence. AppImage remains outside promoted commercial scope pending separate compliance clearance.

## P3 — РЕД ОС / second registry OS acceptance — NEXT TRUSTED-OS GATE

The Astra half of APL-REG-001C is now complete. The remaining second-OS record requires a qualifying РЕД ОС environment and real-host/accepted evidence form.

For РЕД ОС:

1. re-verify qualifying trusted-software status and different-rightsholder condition at execution time;
2. prepare a real host/VM only if the applicable requirement permits the chosen evidence form; prefer a real-host acceptance path consistent with the registry contract;
3. identify exact OS edition/version/build and Proxy Launcher commit/package SHA-256;
4. run clean install, application start/stop, proxy routing/no-proxy, restart/recovery/autostart where applicable, diagnostics/logging, uninstall/removal and post-state;
5. retain dated human acceptance plus raw/machine-readable evidence;
6. only after both Astra + РЕД ОС records exist, resume compatibility reconciliation and registry protocol generation.

Generic Linux CI is not a substitute for these two OS acceptance runs.

Repository preparation is now complete in draft PR `#70` on head `7809e0ab3d8d8e8959676b659a745c20584b6f9e`:

- native x86-64 RPM packaging exists for the governed Linux frozen artifact;
- RED OS strict preflight, privacy-preserving NetworkManager snapshots, exact rollback comparator and fail-closed bundle verifier are implemented;
- all 15 reported PR checks PASS, including RPM build/inspection and RED OS acceptance-tooling contracts;
- current CI RPM: `arvectum-proxy-launcher-0.2.5-1.x86_64.rpm`;
- current RPM SHA-256: `0898b7681b502aaa926876a537d0b4bc6ce5a3c62dc224d7c9b70f03b62665f7`.

The remaining gate is therefore environmental/physical, not repository-tooling work: install the accepted RED OS target, transfer the exact RPM candidate, execute `docs/APL_REG_001C_REDOS_REAL_HOST_ACCEPTANCE.md`, and retain a verifier-complete bundle.

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

- **[Primary local] DONE:** Astra APL-LNX-010 / Gate R8 physical acceptance; first APL-REG-001C trusted-OS record is complete.
- **[Mobile local] READY NOW:** physical Android dogfood for PR #53.
- **[Human] READY NOW:** final APL-IP-001 R-1..R-4 review and decision.
- **[Windows trust] PARALLEL:** APL-REL-016 architecture for `0.2.6+`.
- **[Registry infrastructure] PARALLEL WHEN AVAILABLE:** APL-REG-001B physical sovereign lifecycle proof.
- **[Product discovery] PARALLEL/OPTIONAL:** resolve per-application-routing Windows enforcement architecture.
- **[Second Linux OS] NEXT / ENVIRONMENT REQUIRED:** РЕД ОС real-host acceptance to complete APL-REG-001C.
- **[macOS] DEFERRED:** production signing/notarization when prioritized.
- **[iOS] FUTURE:** after Android dogfood and desktop stability.

## Completion discipline

Do not relabel CI as physical-host/device evidence, detached Russian release evidence as Microsoft native publisher trust, or automation as human/legal approval. Preserve historical identifiers where they are part of immutable evidence. Do not mutate `v0.2.5`. Current operational repository references must use `arvectum2/proxy-launcher`.
