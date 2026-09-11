# Arvectum Proxy Launcher

Arvectum Proxy Launcher is a local proxy launcher with a Windows graphical client. It exposes local HTTP, SOCKS5 and PAC endpoints and routes normal traffic through a configured upstream HTTP proxy; `no_proxy.txt` entries go direct.

## Current canonical status

Windows **0.2.4** is the current physically accepted candidate. Exact candidate commit `e2278dbbd99b0d98ba9e4f836e40b2d60ea94b30` passed APL-WIN-014 on the dedicated `ARVECTUM-DEMO` Windows 11 host under enforced App Control for Business: exact `0.2.3 -> 0.2.4` upgrade, runtime/PAC/WinINET, rollback, repair and uninstall all passed, App Control remained enforced before and after the lifecycle, and the Arvectum-related Code Integrity event `3077` count was zero. The physical closure record is [docs/evidence/APL_WIN_014_FINAL_PHYSICAL_ACCEPTANCE_2026-09-11.md](docs/evidence/APL_WIN_014_FINAL_PHYSICAL_ACCEPTANCE_2026-09-11.md).

The Windows product uses a canonical executable handoff in `%USERPROFILE%\Documents\ArvectumProxyLauncher`, keeps mutable state in `%LOCALAPPDATA%\Arvectum\ProxyLauncher`, protects saved upstream passwords with current-user Windows DPAPI, and includes rollback/recovery, process-ownership, repair/uninstall and supportability safeguards.

Windows Portable and Windows Installer are separate release formats built from the same application binary and canonical `VERSION`:

- `Arvectum-Proxy-Launcher-X.Y.Z-windows-x64-portable.zip`
- `Arvectum-Proxy-Launcher-X.Y.Z-windows-x64-setup.exe`

The Windows installer CI executes the Gate R6 productization chain: final PE/setup metadata verification, RC package acceptance, fresh install smoke, version-transition upgrade, repair and uninstall E2E, plus persistent/foreign-state preservation checks. APL-WIN-014 adds real-host exact-byte lifecycle proof under enforced App Control, including candidate-derived Inno child-runtime trust and exact PyInstaller one-file native-runtime trust.

Production embedded code signing is **not yet activated**. The Russia-first signing architecture and Rutoken/CryptoPro proof are governed separately by APL-REL-009/APL-REL-010 and `RELEASE_POLICY.md`; Windows branding metadata must not be interpreted as a digital signature. Physical acceptance of the `0.2.4` candidate does not itself mean that a public stable release/tag has been published.

macOS and Linux scripts and packaging assets are retained for further integration. Their platform-specific physical/release gates remain separate from the completed Windows APL-WIN-014 acceptance.

## Versioning and releases

See [RELEASE_POLICY.md](RELEASE_POLICY.md) for canonical release, versioning, tag, artifact naming, checksum and signing policies.

- **Current product version:** `0.2.4` (canonical SemVer in `VERSION`).
- **Verified platform track:** Windows `0.2.4` candidate physically accepted by APL-WIN-014; remaining release/signing/legal gates are separate.
- **Accepted product identity:** source commit `e2278dbbd99b0d98ba9e4f836e40b2d60ea94b30`; later documentation-only commits do not change that identity.
- **Release distribution:** Official releases are created by release automation on verified SemVer tags (`vX.Y.Z`) and published to **GitHub Releases** only after applicable gates are satisfied.
- **CI artifacts:** GitHub Actions builds provide QA and pre-release verification packages. Manual release workflow runs execute as dry-runs only.

## Windows installation and support

Use [INSTALL.txt](INSTALL.txt) for the supported Windows installer/upgrade/repair/uninstall path, data locations, Doctor commands and recovery guidance.

Productization and physical-acceptance contracts:

- [APL-WIN-010 — Final executable metadata & Windows branding](APL-WIN-010_FINAL_EXECUTABLE_METADATA_WINDOWS_BRANDING.md)
- [APL-WIN-011 — Release Candidate packaging & acceptance matrix](APL-WIN-011_RELEASE_CANDIDATE_PACKAGING_ACCEPTANCE_MATRIX.md)
- [APL-WIN-012 — Windows RC lifecycle E2E](APL-WIN-012_WINDOWS_RC_E2E.md)
- [APL-WIN-013 — Windows supportability & install docs](APL-WIN-013_WINDOWS_SUPPORTABILITY_INSTALL_DOCS.md)
- [Gate R6 — Windows Productization](GATE_R6_WINDOWS_PRODUCTIZATION.md)
- [APL-WIN-014 — final 0.2.4 physical App Control runbook](docs/APL_WIN_014_FINAL_STAND_RUNBOOK.md)
- [APL-WIN-014 — final physical PASS closure](docs/evidence/APL_WIN_014_FINAL_PHYSICAL_ACCEPTANCE_2026-09-11.md)

## Build and test

### Canonical Windows Clean Build

Prerequisites: Windows x64 with Python 3.12.10 x64.

PowerShell (pwsh):
```powershell
pwsh -NoProfile -File .\tools\clean_build_windows.ps1
```

Windows PowerShell:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\clean_build_windows.ps1
```

Or via compatibility wrapper:
```cmd
build_exe.bat
```

Build outputs:

- `out/Arvectum-Proxy-Launcher-0.2.4-windows-x64-portable.zip` — canonical portable package for the current version
- `out/SHA256SUMS.txt` — portable package checksum
- `out/build-result.json` — build metadata and provenance manifest

Build the canonical Windows installer after the portable executable exists:

```powershell
pwsh -NoProfile -File .\tools\build_windows_installer.ps1
```

### Source testing

```powershell
python -m py_compile proxy_core.py proxy_gui.py
python -m unittest discover -s tests -v
```

## Configuration and recovery

User runtime configuration is created on first use under LocalAppData and is deliberately excluded from Git. No `proxy_settings.json` is bundled in source or CI artifacts. Settings use a versioned, validated schema; writes are same-directory atomic replacements with flush/fsync, and the previous valid configuration is retained as an encrypted last-known-good snapshot. Structurally corrupted settings are quarantined and recovered from that snapshot when possible, otherwise the application uses programmatic safe defaults without silently trusting malformed data. Upstream credentials are stored through current-user Windows DPAPI and are never written as plaintext by the Windows release track.

Do not manually remove recovery files while the proxy is active. Use the launcher's recovery action first; repair/uninstall paths preserve unresolved recovery or foreign state when ownership/safe rollback cannot be proven.

## Releases

The `release/` directory contains supporting documentation and historical artifacts only. Obtain product executables from GitHub Releases or governed CI artifacts; binaries committed in Git history are not canonical release inputs. The physically accepted `0.2.4` candidate remains a release candidate until the separate release, signing and human/legal gates authorize publication.

## License and contribution

See [LICENSE](LICENSE), [SECURITY](SECURITY), [CONTRIBUTING](CONTRIBUTING), and [CODE_OF_CONDUCT](CODE_OF_CONDUCT).
