# APL-IP-002-LNX — Linux stack & dependency sovereignty audit

Status: **CONDITIONAL PASS** for repository/CI scope. Real Astra host acceptance is separately required by APL-LNX-010.

## Runtime dependency inventory

| Component | Class | Origin/control | Bundled | Network dependency | Criticality | Sovereignty treatment |
|---|---|---|---|---|---|---|
| Python runtime frozen by PyInstaller | runtime | Python/PyInstaller ecosystem | yes | no after build | critical | versioned build lock; frozen into artifact |
| Tcl/Tk | runtime/UI | OS/Python distribution | yes in frozen artifact as selected by PyInstaller | no after build | critical GUI | included in THIRD_PARTY_NOTICES; inspect SBOM per release |
| NetworkManager / `nmcli` | host runtime | Linux distribution / NetworkManager project | no | no | critical for system-proxy mutation | fail closed if unavailable; no fallback to ungoverned network stack |
| GLib GSettings / `/usr/bin/gsettings` (`libglib2.0-bin`) | host runtime | Linux distribution / GLib project | no | no | critical for Firefox/system-proxy PAC on Fly/GNOME-family desktops | only the per-user `org.gnome.system.proxy` mode and PAC URL are owned; exact prior values are restored |
| PolicyKit authorization used by NetworkManager | host runtime | Linux distribution | no | no | conditional | Arvectum does not ship/use sudo, pkexec or a password helper; `nmcli --ask` is opt-in only |
| `/etc/os-release`, optional `/etc/astra_version`, XDG environment | host runtime interfaces | distribution standards/files | no | no | detection only | read-only capability detection |
| XDG user config/state/autostart paths | host runtime interfaces | desktop/user session | no | no | product state | user-owned; package lifecycle does not delete or overwrite them |

## Build and packaging dependency inventory

| Component | Class | Pin/provenance control | Distributed to user | Risk |
|---|---|---|---|---|
| `requirements-build.lock.txt` Python build set | build-only | exact package versions | only transitive frozen payload where PyInstaller selects it | PyPI availability is an external build dependency |
| PyInstaller 6.22.0 | build-only + freezer | exact version in build lock | bootloader/frozen runtime contribution | foreign upstream/build-chain dependency |
| `dpkg` / `dpkg-deb` | build-only for `.deb` | Ubuntu/Debian runner package | no | low; replaceable with controlled Debian build host |
| appimagetool 1.9.1 | build-only for AppImage | URL + SHA-256 in `tools/appimage-toolchain.lock` | no | foreign upstream; hash pinned |
| AppImage type-2 runtime | packaged AppImage runtime stub | source commit + SHA-256 in `tools/appimage-toolchain.lock` | yes, as AppImage runtime | foreign upstream; immutable digest is acceptance boundary |
| GitHub-hosted Ubuntu runners | CI/build environment | workflow + runner label | no | external service dependency; not required for end-user runtime |

## External network calls

The application runtime has no required vendor SaaS/API/cloud dependency. Linux system-proxy operation is local and uses host NetworkManager plus the desktop GSettings proxy source on supported Fly/GNOME-family sessions. Network access during build is confined to package/tool acquisition in CI; AppImage acquisition is isolated in `tools/fetch_appimage_toolchain.sh` and verified by SHA-256 before use.

## Replacement / localization options

1. Mirror Python wheels, appimagetool and the pinned AppImage runtime into an Arvectum-controlled or Russian artifact registry while preserving hashes.
2. Run Linux builds on an Arvectum/Russian Debian-compatible runner instead of GitHub-hosted runners; build scripts have no GitHub-specific runtime logic.
3. Keep `.deb` as the primary Russian desktop distribution candidate because it needs no AppImage runtime stub and relies on standard Debian-family package tooling.
4. Keep NetworkManager as an explicit supported-host prerequisite for v1; implementing parallel backends for ifupdown/systemd-networkd would increase attack/recovery surface and is not required for Astra acceptance unless a target Astra configuration proves NetworkManager unavailable.

## Findings

- **LNX-SOV-01 — P1 build sovereignty:** PyPI/GitHub are external build-time supply channels. Mitigation exists through exact versions/digests; self-hosted mirrors remain recommended before sovereign production releases.
- **LNX-SOV-02 — P2 AppImage upstream:** the AppImage runtime is foreign upstream code embedded in the portable artifact. `.deb` avoids this specific dependency and should be preferred for controlled Astra deployments.
- **LNX-SOV-03 — PASS runtime autonomy:** no mandatory external web service is required for normal application operation.
- **LNX-SOV-04 — PASS privilege boundary:** no custom privileged helper, `sudo` or `pkexec` dependency is introduced; authorization remains with NetworkManager/PolicyKit.

## Acceptance

- [x] Runtime/build/package dependencies inventoried and classified.
- [x] Bundled vs host-provided dependencies separated.
- [x] External network dependencies identified.
- [x] Criticality and replacement path recorded.
- [x] AppImage build/runtime inputs hash pinned.
- [x] `.deb` identified as lower-dependency Astra distribution path.
- [ ] Production artifact mirrors inside an Arvectum/Russian-controlled build perimeter — local/infrastructure technical debt, not a v0.2.3 runtime blocker.
- [ ] Real Astra package/runtime acceptance — APL-LNX-010.
