# APL-REG-001C — RED OS physical acceptance

Status: **PASS**

Date: 2026-09-17

## Scope

This protocol qualifies Arvectum Proxy Launcher on the physical RED OS target used for APL-REG-001C. It is an engineering compatibility result, not a legal certification statement and not a claim that Arvectum itself is listed in any government software register.

Target observed on the physical stand:

- RED OS 8.0.3 Standard Desktop;
- x86_64;
- kernel 6.12.101-1.red80.x86_64;
- KDE Plasma / X11 interactive session;
- NetworkManager-managed Wi-Fi connection;
- Chromium supplied for RED OS;
- native RPM/DNF package lifecycle.

Official RED OS material checked on 2026-09-17 identifies RED OS 8.0.3 as the current x86_64 Standard release, identifies ООО «РЕД СОФТ» as the rightsholder, and states registry record №3751 for RED OS. These facts define only the tested OS provenance boundary; they do not extend any registry/certification status to Arvectum Proxy Launcher.

References:

- https://redos.red-soft.ru/product/downloads/
- https://redos.red-soft.ru/product/station/
- https://redos.red-soft.ru/product/red-os/

## Governed candidate

Source branch: `apl-reg-001c-redos-acceptance`

Code-under-test commit before evidence/document finalization: `ad3baea60c32a941a5ab79fc8b1915dee67c1781`.

Package:

`arvectum-proxy-launcher-0.2.6-1.redos8.x86_64.rpm`

Candidate SHA-256:

`7573287133bec48e936330e6563ad4ec144fd83558665f08067e6d3cc7656c0a`

The candidate contains no package-owned `/usr/lib/.build-id` entries, avoiding the build-id ownership collision discovered during the physical RED OS run.

## Compatibility findings and fixes

The first physical run exposed a RED OS-specific desktop integration gap. The existing Linux implementation correctly handled NetworkManager and GSettings desktops, but RED OS 8.0.3 Standard Desktop was running KDE Plasma and already had a user manual proxy in `~/.config/kioslaverc`.

APL-REG-001C therefore added a governed KDE adapter using `kreadconfig5` / `kwriteconfig5` (with KDE 6 utility fallback), read-after-write verification, KIO proxy-change notification, and backend identity in rollback evidence. The rollback contract preserves the pre-existing KDE mode and PAC script instead of replacing unrelated manual proxy keys.

The run also found and fixed RED OS RPM build issues:

- native RPM/DNF packaging rather than reusing the Astra Debian package;
- RPM file-list handling for the executable path containing spaces;
- independence from optional distro brp helper scripts;
- verified frozen-artifact license staging;
- suppression of global build-id links that conflicted with an installed PyInstaller package.

## Physical acceptance results

### Host/package

- Host identity and x86_64 architecture: PASS.
- Native RPM build contract: PASS.
- Final RPM reinstall: PASS.
- `rpm -V arvectum-proxy-launcher`: clean.
- Installed frozen ELF SHA-256 equals the built candidate ELF: PASS.
- Real Plasma/X11 GUI launch: PASS.

### System proxy lifecycle

Pre-test state was captured before mutation. The tested host had NetworkManager proxy method `none` and an existing KDE manual proxy configuration. Sensitive connection identifiers and the user's manual proxy endpoint remain only in the private evidence bundle.

Clean `--start` from the preserved baseline:

- proxy listener `127.0.0.1:18080`: PASS;
- SOCKS listener `127.0.0.1:18081`: PASS;
- PAC listener `127.0.0.1:18082`: PASS;
- NetworkManager `proxy.method=auto`: PASS;
- NetworkManager PAC URL points to local launcher: PASS;
- KDE `ProxyType=2` and local PAC URL: PASS;
- durable rollback evidence records original NetworkManager and KDE states before mutation: PASS.

Clean `--stop`:

- launcher stopped: PASS;
- NetworkManager mechanically compared with pre-test snapshot: PASS;
- KDE `kioslaverc` restored byte-for-byte to its original SHA-256: PASS;
- rollback evidence removed only after successful restoration: PASS.

Emergency `--rollback` from an enabled state:

- launcher stopped: PASS;
- NetworkManager exact baseline comparison: PASS;
- KDE exact byte-for-byte baseline restoration: PASS;
- pending rollback evidence cleared after successful restore: PASS.

### Routing / no-proxy

A local acceptance upstream on `127.0.0.1:19080` and a local direct origin on `127.0.0.1:19081` were used so the proof did not depend on an external proxy service.

- launcher HTTP transport to acceptance upstream: PASS;
- generated PAC contains the governed no-proxy list and defaults to `PROXY 127.0.0.1:18080`: PASS;
- fresh GUI Chromium profile, launched without explicit proxy flags, requested `http://proxy-route.invalid/gui-proof-003` through the system PAC and launcher: PASS;
- Chromium request to `http://localhost:19081/direct-proof-002` reached the direct origin and bypassed the upstream: PASS.

Headless Chromium was not used as browser acceptance evidence because the RED OS headless invocation did not consume the desktop proxy source consistently. The normal Plasma/X11 Chromium session is the governed browser result.

### Autostart

On the installed canonical ELF, XDG autostart ownership round-trip was exercised physically:

- initial Arvectum autostart entry absent: PASS;
- enable creates the exact owned desktop entry pointing to `/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher --start`: PASS;
- status reports managed/enabled: PASS;
- disable removes only the owned entry: PASS;
- final state equals the initial absent state: PASS.

### Diagnostics

The Linux support bundle collector created a redacted ZIP with schema `arvectum.proxy.linux_diagnostics.v1`, `diagnostics.json`, and bounded structured logs. It included the system/runtime/application/proxy/NetworkManager/autostart/recovery/listener/policy sections expected by the Linux collector.

NetworkManager snapshots before and after diagnostics compared equal, and the KDE proxy configuration hash was unchanged: PASS.

## Evidence handling

Raw physical evidence is retained privately at:

`~/APL-REG-001C-20260917-090901`

It is intentionally not committed verbatim because it can contain local usernames, connection metadata, local paths, and the user's pre-existing proxy configuration. Repository evidence is a sanitized summary with hashes and pass/fail facts only.

## Final privileged package lifecycle

The closeout gate was executed through the normal local PolicyKit/DNF authorization path without storing or exposing any password.

- privileged `dnf remove arvectum-proxy-launcher`: PASS;
- `rpm -q` after removal reports the package absent: PASS;
- no package-owned payload remains after removal: PASS;
- NetworkManager and KDE remain exactly at the captured baseline after removal: PASS;
- clean install of the exact RPM SHA-256 `7573287133bec48e936330e6563ad4ec144fd83558665f08067e6d3cc7656c0a`: PASS;
- `rpm -V arvectum-proxy-launcher` after clean install: PASS;
- installed ELF SHA-256 `e6f26d6be36b5e7218fbe6e11679bf9dc99e4af2b90f602db0899e0fda48912f` equals the candidate payload ELF: PASS;
- final clean `--start` raised listeners `18080/18081/18082`, applied KDE/NetworkManager PAC state, and created durable rollback evidence: PASS;
- final `--stop` restored NetworkManager exactly and restored `kioslaverc` byte-for-byte to SHA-256 `1c6a823fa976f465adf012e85aeb55d965c8df379cfb72f7f9f4c56733f3fbde`: PASS;
- rollback backup removed and original absent autostart state preserved: PASS;
- acceptance-only local stubs on ports 19080/19081 and temporary Chromium profiles removed: PASS.

Final focused RED OS regression suite: **62/62 PASS**. Pre-finalization exact-head GitHub Actions for commit `9bc3867be324a4fed80b81ff3f80cd989140134c`: **13/13 workflows PASS**.

APL-REG-001C physical RED OS acceptance result: **PASS**.
