# APL-IP-002 — Russian stack & dependency sovereignty audit

Status: **AUDIT COMPLETE / REMEDIATION HANDED OFF**  
Audit date: **2026-09-13**  
Baseline: `main` @ `c6a93e096eedde7be23ade93cd7372a04db311a0`  
Tracking issue: #52  
Machine-readable contract: `compliance/APL_IP_002_STACK_SOVEREIGNTY.json`

## 1. Decision

APL-IP-002 separates **ownership/compliance of the product code** from **origin of tools and services used around the product**. A foreign or international open-source component is not treated as an automatic failure of the Russian Software Registry requirements. Conversely, merely mirroring a repository to a Russian service is not treated as proof that the complete lifecycle infrastructure satisfies Government Resolution No. 1236.

The audit result is:

- **runtime vendor-cloud independence: PASS**;
- **Windows offline/hash-locked build capability: PASS**;
- **third-party notice/SBOM/provenance automation foundation: PASS**;
- **sovereign source/object-code storage: PARTIAL**;
- **sovereign build/CI: MISSING as a filing-grade governed path**;
- **sovereign artifact distribution: PARTIAL**;
- **foreign-payment/accounting review: EXTERNAL PENDING**;
- **release-bound legal disposition: PENDING APL-IP-001**.

Therefore APL-IP-002 itself can close as an inventory/audit task. Infrastructure remediation moves to **APL-REG-001B**, while final release-bound IP/license/human-authorship evidence moves to **APL-IP-001**.

## 2. Runtime finding: no Arvectum cloud control plane

The current product is unusually favourable from a sovereignty perspective because the traffic path is local and configuration-driven.

`local_proxy_transport.py` uses Python standard-library socket/select/threading/base64 primitives. The endpoints contacted at runtime are:

1. the destination requested by the user/application when a bypass rule selects direct access; or
2. an **upstream proxy host supplied in the user's settings**.

No mandatory Arvectum API, telemetry endpoint, vendor license server, update service or cloud control plane is present in the audited runtime contract. The configured upstream proxy is therefore classified `USER_SUPPLIED`, not as an Arvectum SaaS dependency.

This does **not** mean the application is an offline product: network access is its purpose. It means the product does not require a vendor-controlled foreign service in order to start, configure or route traffic.

## 3. Runtime and packaged third-party stack

### 3.1 CPython / standard library

Canonical Windows build Python is pinned to **3.12.10**. Frozen desktop artifacts include the selected Python runtime/standard-library components. Python is global open source governed by the Python Software Foundation license and incorporated component licenses.

Disposition: **allowed as a governed third-party runtime component**, subject to exact release SBOM/license evidence. No automatic replacement requirement is created by APL-IP-002.

### 3.2 Tcl/Tk / Tkinter

The current GUI uses Tkinter; selected Tcl/Tk runtime components may therefore be present in frozen artifacts. `THIRD_PARTY_NOTICES.txt` already records BSD-style Tcl/Tk licensing.

Disposition: release-bound license evidence required; not a cloud/network dependency.

### 3.3 PyInstaller runtime contribution

PyInstaller is primarily build tooling, but its generated bootloader/runtime contribution is part of a frozen executable. The project permits commercial bundles under its GPL exception; selected files use Apache-2.0.

Disposition: do not call the whole PyInstaller package an application runtime dependency, but do include actual bootloader/runtime contributions in artifact-level license/SBOM evidence.

## 4. Windows build stack

The canonical lock contains:

- `altgraph==0.17.5`;
- `packaging==26.3`;
- `pefile==2024.8.26`;
- `pyinstaller==6.22.0`;
- `pyinstaller-hooks-contrib==2026.6`;
- `pywin32-ctypes==0.2.3`;
- `setuptools==84.0.0`.

The clean build also pins `pip==26.1.2`.

These are classified as global open-source **build dependencies**, not vendor SaaS. Exact entries and dispositions are in the JSON contract.

### 4.1 Offline build is already architected

`tools/clean_build_windows.ps1` accepts `-WheelhousePath`. In that mode it:

- sets `PIP_NO_INDEX=1`;
- uses `--no-index`;
- uses only the approved local wheelhouse;
- uses `--require-hashes`;
- consumes `requirements-build.windows-x64.hashes.txt`;
- disables dependency resolution with `--no-deps`.

`requirements-build.windows-x64.hashes.txt` contains approved SHA-256 values for the complete Windows build set, including pip.

This means **PyPI availability is not an architectural production-build dependency**. For registry preparation APL-REG-001B should promote the offline wheelhouse mode from an available capability to the governed production/release path and place the approved wheelhouse/evidence in the Russian-controlled lifecycle boundary.

### 4.2 Inno Setup

The Windows installer path requires exact **Inno Setup 6.7.1** and records the compiler SHA-256. Inno Setup is foreign build tooling, but is not bundled as an application runtime component.

Disposition: conditional lifecycle dependency, not an automatic registry blocker. Retain version/hash evidence; assess replacement only if the final legal/infrastructure interpretation makes that necessary.

## 5. Linux / trusted-OS path

The Linux packaging path depends on host-provided Linux components including NetworkManager/PolicyKit integration. The Debian packaging CI installs `python3-venv`, `python3-tk`, `dpkg-dev` and `file`, while the produced Debian package declares a NetworkManager dependency.

For APL-REG-001C the legal/technical unit of evidence is not generic Ubuntu CI. It is the **exact package set and behaviour on the two selected trusted Russian operating systems**.

The AppImage path additionally uses hash-pinned `appimagetool` and a hash-pinned type-2 runtime. Because a native Debian-style packaging path also exists, AppImage is not a hard dependency for registry compatibility.

Disposition: keep AppImage for distribution convenience; prefer native packaging/evidence appropriate to the selected trusted OSes for registry acceptance.

## 6. Platform dependencies are not source-code ownership

### Windows

WinINET/Windows APIs/PowerShell are host/platform dependencies for the Windows target. They are foreign platform technology, but they are not third-party source incorporated into Arvectum's repository merely because the application calls OS APIs.

### Linux

NetworkManager/PolicyKit and distribution packages are host components and must be validated on each selected trusted OS.

### macOS

Apple system tools such as `hdiutil` are platform/build dependencies for the macOS distribution path. They are outside the current Russian-registry compatibility target unless the application dossier chooses to make them relevant.

The registry strategy is therefore **multi-platform**, not an attempt to pretend that Windows itself is Russian software.

## 7. CI, source storage and distribution — principal sovereignty gap

### 7.1 GitHub

Current engineering relies materially on GitHub for source collaboration, GitHub Actions CI, workflow artifacts and canonical public releases. This is classified as a **foreign cloud lifecycle dependency**.

APL-IP-002 does not claim this alone makes the program ineligible. It does conclude that GitHub cannot be the evidence used to prove a Russian-controlled lifecycle requirement where Resolution No. 1236 requires Russian technical infrastructure.

Required APL-REG-001B action:

- establish the authoritative Russian storage boundary for source and object code;
- establish a controlled Russian build/CI path;
- make production build independent of GitHub and PyPI availability;
- establish filing-grade Russian artifact/release storage and distribution evidence;
- retain GitHub only as an additional collaboration/mirror/public channel to the extent legally acceptable.

### 7.2 GitVerse

GitVerse is already used as a Russian mirror. SberTech publicly identifies itself as the operator of GitVerse and describes it as a Russian source-code platform.

That is useful, but **mirror status is not enough**. APL-REG-001B must record physical/service control, artifact storage, CI runner location/control and the exact authoritative role assigned to GitVerse. GitVerse can be promoted to part of the sovereign lifecycle only after that evidence exists.

## 8. Security/SBOM/provenance tooling

Existing GitHub Actions run:

- dependency vulnerability scanning;
- CycloneDX SBOM generation;
- source provenance checks;
- SAST and secret scanning.

These are assurance controls, not application runtime dependencies. The sovereignty solution is **not to delete security checks**. It is to run the same or equivalent gates on the Russian/self-hosted production path while retaining current checks as defence in depth.

## 9. Signing

The existing CryptoPro/Rutoken detached release-evidence path is a Russian signing layer and is classified separately from Microsoft Authenticode public trust.

Private keys, token contents and UKЭП material must remain outside the repository. Only public verification/evidence belongs in release assets.

## 10. THIRD_PARTY, SBOM and provenance state correction

The earlier APL-REG-001 readiness matrix understated current maturity:

- `THIRD_PARTY_NOTICES.txt` already exists and distinguishes runtime/build/OS components;
- CycloneDX SBOM automation already exists;
- APL-IP-001 source provenance automation already exists;
- installer/portable packaging already carries a governed third-party license bundle contract.

They are therefore not `MISSING`. They remain **PARTIAL** until bound to the exact registry-submitted release with final legal/human review.

## 11. What is not solved by this audit

APL-IP-002 intentionally does not manufacture evidence that belongs outside the repository. Still open:

- accounting/legal determination of payments to foreign rightsholders/providers and any applicable statutory threshold or restriction;
- final corporate exclusive-right chain;
- physical/service-location proof for lifecycle infrastructure;
- final selection of Russian authoritative source/build/artifact infrastructure;
- human authorship review and OSS overlap review;
- release-bound legal sign-off and clean-IP baseline/tag.

These are explicit handoffs, not hidden gaps.

## 12. Governed conclusion

For the current product architecture the main sovereignty risk is **not a mandatory foreign runtime cloud or proprietary proxy backend**. It is the current **development/build/release control plane** around the product.

That is favourable because the remediation can be concentrated in the lifecycle:

**Arvectum-owned source + governed OSS → offline/hash-locked build → Russian-controlled CI/build storage → Russian artifact/release channel → release-bound SBOM/licenses/provenance → CryptoPro/Rutoken evidence**, while GitHub remains optional rather than authoritative for the Russian filing path.

APL-IP-002 is complete when the machine-readable inventory and its invariants pass CI. Remediation/evidence items remain blocking in APL-REG-001B and final IP/legal work remains blocking in APL-IP-001.
