Arvectum Proxy Launcher — Windows Portable
==========================================

QUICK START

1. Extract the ZIP into a normal writable folder.
2. Run "Arvectum Proxy Launcher.exe".
3. Configure the upstream proxy and verify connectivity before enabling autostart.

DATA LOCATIONS

The launcher uses a stable executable location when Windows permits it:
  %USERPROFILE%\Documents\ArvectumProxyLauncher

Persistent settings, no-proxy rules, logs and recovery state are stored in:
  %LOCALAPPDATA%\Arvectum\ProxyLauncher

SAFETY

* Do not move or delete the executable while the proxy is active.
* Do not delete the LocalAppData state directory while rollback/recovery is pending.
* If the stable Documents handoff is blocked, the current portable session can continue,
  but autostart remains disabled and existing startup entries are not redirected.
* Saved upstream passwords are protected for the current Windows user with DPAPI.

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
