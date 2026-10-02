Arvectum Proxy Launcher — Windows Portable
==========================================

QUICK START

1. Extract the ZIP into a normal writable folder.
2. Run "Arvectum Proxy Launcher.exe".
3. Configure the upstream proxy and verify connectivity before enabling autostart.

APPLICATION EXCLUSIONS

Per-application exclusions use the production WinDivert routing component bundled
inside this portable package. Nothing is installed merely by starting the launcher.
The first time you save a non-empty application-exclusion list, Windows may ask once
for normal administrator consent so Arvectum can install its exact verified routing
service. Do not disable Secure Boot, Memory Integrity, antivirus, or other Windows
security features.

DATA LOCATIONS

The launcher uses a stable executable location when Windows permits it:
  %LOCALAPPDATA%\Programs\ArvectumProxyLauncher

Persistent settings, no-proxy rules, logs and recovery state are stored in:
  %LOCALAPPDATA%\Arvectum\ProxyLauncher

SAFETY

* Do not move or delete the executable while the proxy is active.
* Do not delete the LocalAppData state directory while rollback/recovery is pending.
* If the stable LocalAppData handoff is blocked, the current portable session can
  continue, but autostart remains disabled and existing startup entries are not redirected.
* Saved upstream passwords are protected for the current Windows user with DPAPI.
* The bundled WinDivert component is verified against pinned hashes and signer identity
  before installation; a mismatch fails closed instead of weakening Windows security.

DIAGNOSTICS

The package includes diagnose_app_control.ps1 for Windows App Control diagnostics and
run_p01_native_qa_v2.ps1 for native execution QA. The executable also supports the
read-only commands --doctor and --doctor-json.

INTEGRITY AND SIGNING

Use the SHA256SUMS.txt supplied with the package/release to verify downloaded bytes.
Windows production code signing is governed separately by the release policy; do not
interpret file metadata or the Arvectum icon as a digital-signature trust assertion.

Support and release policy:
  https://github.com/arvectum2/proxy-launcher
