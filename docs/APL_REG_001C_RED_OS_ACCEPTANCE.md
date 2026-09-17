# APL-REG-001C — RED OS real-host acceptance

Status: **IN PROGRESS — physical RED OS 8.0.3 stand identified; native RPM packaging implemented; privileged install/runtime phases pending ordinary PolicyKit authorization.**

## Purpose

Complete the second real-host trusted-Russian-OS compatibility run required by `APL-REG-001_RUSSIAN_SOFTWARE_REGISTRY_READINESS.md`. The first run is the completed Astra Linux Special Edition 1.8 acceptance. This document governs the RED OS half; it does not replace the final legal recheck immediately before a Russian Software Register filing.

## Tested host

Read-only evidence captured on 2026-09-17 identifies the physical stand as:

- product: RED OS;
- exact installed edition: `RED OS 8.0.3 (Standard Desktop)` / `EDITION=Standard`;
- architecture: x86_64;
- kernel: `6.12.101-1.red80.x86_64`;
- graphical environment: KDE Plasma, X11;
- virtualization detection: `none`;
- NetworkManager: 1.52.2-2.red80;
- package format/tooling: RPM/DNF;
- physical model reported by DMI: HP EliteBook 735 G6.

The canonical collector is `qa/collect_redos_acceptance_preflight.py`. It is read-only and deliberately records no raw NetworkManager UUIDs, PAC content, credentials or home-directory inventory.

## Qualification/rightsholder recheck at execution time

Public vendor evidence rechecked on 2026-09-17:

- RED OS product page: https://redos.red-soft.ru/product/red-os/ — identifies RED OS as included in the Russian software register under record 3751 and identifies ООО «РЕД СОФТ» as rightsholder.
- RED OS 8 certification notice: https://redos.red-soft.ru/about/news/novosti/red-os-8-sertifitsirovana-fstek-rossii/ — states that RED OS 8 completed FSTEC certification testing in December 2025 under certificate 4060.
- RED SOFT accredited-company disclosure: https://www.red-soft.ru/ru/node/3761 — states that ООО «Ред Софт» develops and is the rightsholder of RED OS, register record 3751.
- Astra Linux accredited-company disclosure: https://astralinux.ru/accredited-company/ — identifies ООО «РусБИТех-Астра» as developer/rightsholder of Astra Linux Special Edition, register record 369.

These sources support the engineering decision to execute the planned pair on products with different disclosed rightsholders. They are not a substitute for the mandatory current-law/classifier/trusted-software recheck at filing time.

## Candidate identity

The acceptance is anchored to stable release `v0.2.6`, not to a new application build.

Canonical public Astra/Linux release package:

- file: `Arvectum-Proxy-Launcher-0.2.6-astra-linux-amd64.deb`;
- SHA-256: `1176ca8c7a97d0eb173a76fd108460e9fada1bcb70fb1819029f299a30dcbc20`;
- release: https://github.com/arvectum2/proxy-launcher/releases/tag/v0.2.6.

On the RED OS stand the public DEB was downloaded and independently re-hashed. Its application payload was extracted without installation. The exact frozen Linux ELF has SHA-256:

`8ecd148ff7d84711c180f517a86dea4f6c50f780ca71fb1f06e17131ac7f39e9`

That exact ELF starts on RED OS 8.0.3 and reports `STOPPED` through `--status`. It is wrapped unchanged in the native RPM acceptance candidate. This preserves application-byte identity with the already-published v0.2.6 Linux payload while adding the package format required by RED OS.

## Native RED OS package

`tools/build_linux_rpm.sh` defines the governed RPM packaging path. It mirrors the Debian package ownership boundary:

- application: `/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher`;
- launcher: `/usr/bin/arvectum-proxy-launcher`;
- freedesktop desktop entry and icon;
- license, third-party notices and third-party license bundle;
- dependencies: `NetworkManager`, `glib2`;
- no `%pre`, `%post`, `%preun` or `%postun` lifecycle scripts;
- package installation/removal never changes NetworkManager, desktop proxy or per-user XDG state.

The first physical-stand candidate was created locally on RED OS from the exact public v0.2.6 ELF:

- RPM NEVRA: `arvectum-proxy-launcher-0.2.6-1.redos.red80.x86_64`;
- stand candidate SHA-256: `1d1e1d9ff89b0b68403af2e8ee34371e982dcb7807c536717e48af068c92fb95`.

This stand-built RPM is acceptance evidence, not a retroactive mutation of the immutable v0.2.6 GitHub release. A CI-built RPM artifact is separately required before promotion/distribution decisions.

## Baseline network state

Before installation or product mutation, the real host reported:

- no Arvectum package installed;
- application listeners 127.0.0.1:8080 and 127.0.0.1:8082 absent;
- desktop GSettings proxy mode `none`, autoconfig URL empty;
- active Wi-Fi NetworkManager profile proxy method `none`, PAC URL absent;
- no pre-existing Arvectum rollback state observed through the exact v0.2.6 status/doctor paths.

The NetworkManager permission model reports `settings.modify.system=auth`. Therefore proxy activation on the current system-owned Wi-Fi profile must remain inside the normal PolicyKit authorization path; the acceptance must not bypass this protection.

## Required physical acceptance phases

The final run must retain evidence for all of the following:

1. **Clean install** — install the governed RPM through the normal RPM/DNF/PackageKit trust boundary; verify package metadata, launcher, desktop entry and exact ELF hash.
2. **Idle start/status** — package launches in KDE/X11 and reports a clean stopped state before enablement.
3. **Proxy routing** — with an acceptance-only upstream, prove a request not in bypass rules traverses the local Arvectum listener and the selected upstream.
4. **No-proxy/bypass** — prove an acceptance-only bypass target is connected directly and is not sent to the upstream; restore the original bypass configuration afterward.
5. **System-proxy publication** — verify owned PAC publication through both NetworkManager and desktop GSettings on RED OS, with localhost PAC reachable.
6. **Normal stop/rollback** — compare post-stop NetworkManager and desktop proxy state mechanically to the captured baseline; no pending rollback may remain.
7. **Autostart/login** — verify the governed per-user XDG autostart entry and one graphical-login launch; toggling autostart alone must not alter proxy state.
8. **Crash/recovery** — terminate the running application without a normal disable, relaunch and prove pending recovery remains detectable and exact rollback succeeds.
9. **Restart/recovery** — where the stand can be restarted safely, repeat the pending-rollback recovery path across a normal reboot/login.
10. **Diagnostics/log collection** — generate the Linux support evidence needed to investigate a failure while excluding credentials, raw rollback payloads, browser history and unrelated user files.
11. **Clean uninstall** — only from a clean proxy state, remove the RPM and prove removal does not masquerade as rollback or erase unrelated user-owned state.
12. **Final post-state** — application package absent, listeners closed, network/desktop proxy equal to the baseline, no pending rollback, acceptance-only configuration removed.

## Safety invariants

- Never install/remove the package while an owned proxy rollback is pending.
- Never use a generic proxy reset to manufacture a passing rollback result.
- Never overwrite a foreign/newer proxy change merely to satisfy acceptance.
- Never weaken PolicyKit or change NetworkManager ownership/permissions to make the test easier.
- Never store proxy credentials or raw PAC/connection identifiers in repository evidence.
- `PASS` is forbidden until final network state is mechanically equivalent to the captured baseline.

## Current execution state

Completed on the physical RED OS host:

- exact host/edition/kernel/desktop/package-system identification — PASS;
- non-virtualized physical-host attestation — PASS;
- exact public v0.2.6 DEB download and SHA-256 verification — PASS;
- extraction and execution of the exact v0.2.6 Linux ELF — PASS (`--status` returned `STOPPED`);
- native RPM candidate generation from that unchanged ELF — PASS;
- read-only RED OS acceptance preflight — PASS;
- RPM/DEB packaging contract regression suite — PASS.

Pending physical phases require normal administrator authorization for package installation and NetworkManager system-profile mutation. A PackageKit install attempt correctly stopped at authentication rather than bypassing the privilege boundary.

Final acceptance verdict remains **OPEN** until those phases are executed and recorded.
