# APL-REG-001C — RED OS RPM preparation

Status: **repository/CI preparation; physical RED OS acceptance still required**.

## Purpose

Prepare a native RPM distribution path for the second trusted-OS acceptance record without pretending that CI proves RED OS compatibility. The existing Debian package remains the governed Astra/Debian-family path; this RPM is the installation vehicle intended for the RED OS real-host run.

RED OS 8 documents RPM/DNF as its native package-management path and supports installation of a local RPM with `dnf install <path-to-package.rpm>`. Its workstation target includes x86_64, matching the current physical acceptance scope.

## Package contract

`tools/build_linux_rpm.sh` consumes the same frozen Linux application artifact used by the Debian packaging lane and creates:

`dist/rpm/arvectum-proxy-launcher-<version>-1.<dist>.x86_64.rpm`

Installed payload:

- `/opt/arvectum-proxy-launcher/Arvectum Proxy Launcher` — frozen application;
- `/usr/bin/arvectum-proxy-launcher` — stable launcher wrapper;
- `/usr/share/applications/arvectum-proxy-launcher.desktop` — desktop registration;
- `/usr/share/icons/hicolor/256x256/apps/arvectum-proxy-launcher.png` — icon;
- `/usr/share/doc/arvectum-proxy-launcher/` — project license, notices and third-party license bundle.

The RPM requires `NetworkManager`, which matches the governed Linux backend. It deliberately contains no `%pre`, `%post`, `%preun`, `%postun`, trigger or system-wide autostart scriptlets. Package installation/removal therefore cannot itself enable a proxy, mutate NetworkManager proxy settings, request PolicyKit elevation, or delete per-user configuration/recovery/autostart state.

## CI boundary

The RPM workflow may prove packaging structure, dependencies, absence of lifecycle scriptlets, payload identity and basic binary startability in a Fedora-family build container. It **does not** constitute a RED OS acceptance result.

A physical or otherwise explicitly accepted RED OS evidence run must still record:

1. exact RED OS edition/version/build and architecture;
2. exact repository commit and RPM SHA-256;
3. clean local RPM installation with DNF and successful GUI/runtime start;
4. NetworkManager preflight plus real enable/no-proxy/disable behavior;
5. exact post-disable rollback to the captured baseline;
6. autostart/login behavior where applicable;
7. crash/relaunch and reboot/login recovery;
8. diagnostics/privacy inspection with no proxy credentials copied into evidence;
9. update/removal behavior and preservation of user-owned state;
10. final proxy state OFF/baseline and dated human host attestation.

Only that RED OS evidence, together with the already completed Astra record, may unblock APL-REG-001C compatibility reconciliation and registry protocol generation.
