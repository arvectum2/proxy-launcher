# Release and Version Policy

## 1. Canonical Repository and Sources

* **Canonical source of truth:** GitHub repository [`arvectum2/proxy-launcher`](https://github.com/arvectum2/proxy-launcher).
* **Canonical integration branch:** `main`.
* **Mirrors:** External mirrors (e.g., GitVerse) are downstream mirrors and do not serve as an independent source of truth.
* **Release binaries:** Pre-built binary archives (ZIP, EXE, DMG, tarball) committed directly into Git are historical artifacts only and are **not** canonical release distribution sources.

## 2. Versioning Scheme

Arvectum Proxy Launcher strictly follows **Semantic Versioning (SemVer 2.0.0)**:

```text
MAJOR.MINOR.PATCH
```

* **MAJOR:** Incompatible architectural shifts or breaking public contract changes (after 1.0.0).
* **MINOR:** New user features, capabilities, or verified platform support.
* **PATCH:** Bug fixes, security hotfixes, recovery stabilization, or packaging corrections without new functional scope.

While product versions are below `1.0.0` (e.g. `0.2.3`), minor releases may contain non-backward-compatible improvements, accompanied by mandatory release notes.

### Current Version Status
* **Canonical Product Version:** `0.2.3`
* The presence of a version number in code or documentation indicates the software version baseline, **not** that a public release has already been published.

## 3. Engineering Milestones vs. Product Versions

Engineering milestones and backlog markers (such as `P0`, `P0.2`, `P0.4`, `RC2`, `final`, `latest`, `fixed`) represent internal project planning and QA milestones.

**Rules:**
* Engineering milestones are strictly internal metadata.
* Milestones are **never** part of the canonical product version string.
* Milestones must not be embedded in:
  * Public Git tags (`v0.2.3`, not `v0.2.3-P0.2` or `0.2.3 P0.2`).
  * GitHub Release titles or tags.
  * Windows executable metadata (`ProductVersion`, `FileVersion`).
  * Canonical release artifact filenames.
* Valid prerelease identifiers follow SemVer specifications only (e.g., `0.2.4-rc.1`, `0.3.0-beta.1`).

## 4. Git Tags

* **Stable releases:** `vX.Y.Z` (e.g., `v0.2.3`, `v0.2.4`, `v0.3.0`).
* **Prerelease builds:** `vX.Y.Z-prerelease.N` (e.g., `v0.2.4-rc.1`, `v0.3.0-beta.1`).

**Tag Rules:**
1. Release tags are **immutable**. Once published, a tag must never be moved or replaced.
2. Release tags must point directly to a commit on `main` that has green CI status.
3. If an issue is discovered after tagging/releasing, do not modify the tag; issue a new `PATCH` release.

## 5. Canonical Clean Build and Toolchain

Windows builds use a single canonical clean-build script:

* **Entrypoint:** `tools/clean_build_windows.ps1` (with `build_exe.bat` as a thin compatibility wrapper).
* **Base Python:** `3.12.10` x64 pinned in `BUILD_PYTHON_VERSION`.
* **Build toolchain:** Exact pinned dependencies in `requirements-build.lock.txt` (`pip==25.3`, `pyinstaller==6.22.0`).
* **Isolation:** Every build operates in a fresh, isolated virtual environment (`.build-venv`), preventing ambient/global package interference.
* **Process:** Clean -> venv -> install lock -> py_compile -> unit tests -> PyInstaller -> package -> internal/external SHA256 -> verify -> `build-result.json`.

## 6. Canonical Release Pipeline and Automation

Canonical distribution flow:
```text
source change
  -> Pull Request
  -> main
  -> green CI (via tools/clean_build_windows.ps1)
  -> version consistency validation
  -> Git tag (vX.Y.Z)
  -> GitHub Release workflow (.github/workflows/release.yml)
  -> canonical Windows build & smoke QA
  -> public SHA256SUMS.txt generation
  -> GitHub Release publication
```

* **Workflow definition:** `.github/workflows/release.yml`.
* **Real publication triggers:** Only pushes of matching SemVer tags (`v*.*.*`) can trigger publication.
* **Tag consistency:** Pushed tag must strictly equal `v${VERSION}` (where `${VERSION}` is read from `VERSION`).
* **Main ancestry:** Tagged commit must be an ancestor of `origin/main`.
* **Prior green main CI:** Tagged commit must have a preceding successful push run on `main` for the canonical Windows workflow.
* **Manual runs & PRs:** `workflow_dispatch` and `pull_request` triggers run validation and reusable Windows builds in safe dry-run mode and **never** publish releases.
* **Assets published:** Canonical Windows portable ZIP (`Arvectum-Proxy-Launcher-X.Y.Z-windows-x64-portable.zip`), Windows Installer (`Arvectum-Proxy-Launcher-X.Y.Z-windows-x64-setup.exe`), and one external checksum manifest (`SHA256SUMS.txt`) covering both.
* **Prerelease handling:** SemVer prerelease identifiers (e.g. `0.2.4-rc.1`) are automatically flagged as GitHub prereleases.
* **Immutability:** Existing GitHub Releases cannot be overwritten or clobbered (`--clobber` is prohibited). Duplicate release attempts fail.
* **Developer workstation builds:** Binaries built on developer workstations are strictly for local testing and debugging. They are not canonical release artifacts.
* **CI Artifacts vs. GitHub Releases:** GitHub Actions artifacts are temporary QA and pre-release test builds. GitHub Releases is the canonical public binary distribution channel.

### 6.1 Russian production signing policy

The canonical production trust strategy for the Russian market is defined by `release/APL_REL_009_RUSSIAN_PRODUCTION_SIGNING_ARCHITECTURE.md`.

* The release-signing priority is **Russia first**.
* The existing ООО «Арвектум» Rutoken-backed УКЭП is used for qualified detached signature of final release evidence once the real POC is completed.
* The intended embedded code-signing direction is ОТУЦ or an equivalent successor Russian code-signing mechanism after certificate profile, timestamping and target-OS verification are proven.
* A normal qualified certificate must **not** be assumed to be a Windows code-signing certificate; embedded signing requires a separately proven certificate/provider profile.
* Production private keys must remain non-exportable and owner-controlled; PFX/P12 export and token PIN storage in repository/cloud CI secrets are prohibited.
* Foreign code-signing providers are deferred to a future international compatibility track and are not a blocker for the Russian production baseline.
* Production Russian signing is **not yet activated**. APL-REL-010 must prove the real Rutoken/CryptoPro signing path before release publication is changed.

When Russian production signing is activated, the release flow must produce and publish at minimum `SHA256SUMS.txt`, `SHA256SUMS.txt.sig`, the signer certificate/public chain material required for verification, and non-secret `signing-evidence.json`.

## 7. Canonical Artifact Naming

Standard release filenames:

* **Windows Portable:** `Arvectum-Proxy-Launcher-X.Y.Z-windows-x64-portable.zip`
* **Windows Installer:** `Arvectum-Proxy-Launcher-X.Y.Z-windows-x64-setup.exe`

The installer is built from the same portable application binary and `VERSION` using `tools/build_windows_installer.ps1`. The repository contains an **Authenticode foundation** in `tools/windows_authenticode.ps1` and `.github/workflows/windows-authenticode.yml`, but **production signing is not yet activated**. APL-REL-009 makes the Russian signing architecture canonical. When embedded production code signing is activated, the portable application executable must be signed before portable packaging, and the installer executable must be signed after Inno Setup compilation; both signatures must be verified against the expected publisher before final checksums. The final checksum manifest is then qualified-signed through the approved Russian Rutoken/CryptoPro path before publication.
* **macOS Apple Silicon:** `Arvectum-Proxy-Launcher-X.Y.Z-macos-arm64.dmg`
* **macOS Intel:** `Arvectum-Proxy-Launcher-X.Y.Z-macos-x64.dmg` (when supported)
* **Linux x86_64:** `Arvectum-Proxy-Launcher-X.Y.Z-linux-x86_64.tar.gz`
* **Checksum Manifest:** `SHA256SUMS.txt`

## 8. Checksum Manifest Policy

* Release checksums must be published in standard `SHA256SUMS.txt` format:
  ```text
  <sha256>  <filename>
  ```
* For GitHub Releases, `SHA256SUMS.txt` must cover all final downloadable release packages (ZIP, EXE, DMG, tar.gz) and portable executables.
* Once the Russian production signing path is activated, checksum generation must occur after every byte-changing embedded signature operation, and the final manifest must be covered by the approved detached Russian electronic signature.

## 9. Platform Release Maturity

* **Windows (0.2.3):** Verified production track with Documents handoff, LocalAppData isolation, DPAPI credential protection, rollback/recovery, and process-ownership enforcement.
* **macOS:** Retained for continued development; not verified for production release until dedicated CI build and verification gates are implemented.
* **Linux:** Retained for continued development; not verified for production release until dedicated CI build and verification gates are implemented.
