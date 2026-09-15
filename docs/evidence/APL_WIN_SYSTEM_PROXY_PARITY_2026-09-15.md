# Windows system-proxy parity audit — 2026-09-15

## Question

Verify whether the Windows build can suffer the same integration failure fixed for Astra/Fly in the Linux 0.2.6 work: the launcher reports system proxy active, but Firefox in **Use system proxy settings** does not consume the PAC because the launcher published the configuration into a different operating-system settings plane.

## Linux defect being compared

The Astra/Fly failure was a split-settings-plane problem. Proxy Launcher 0.2.5 published the PAC through NetworkManager, while Firefox `network.proxy.type=5` on the tested desktop consumed the desktop GSettings proxy configuration. Linux 0.2.6 added governed `org.gnome.system.proxy` publication and exact rollback alongside NetworkManager.

## Windows implementation audit

Windows does not use the Linux dual-plane arrangement. `windows_system_proxy.py` publishes the governed PAC URL directly as the current user's WinINET `AutoConfigURL` under:

`HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings`

On enable it also disables the parallel manual proxy flag (`ProxyEnable=0`), preserves the previous Internet Settings state before mutation, updates the per-user proxy environment for non-WinINET consumers, enables recovery ownership, and calls WinINET `InternetSetOptionW` with `INTERNET_OPTION_SETTINGS_CHANGED` and `INTERNET_OPTION_REFRESH` so existing WinINET consumers are asked to re-read the proxy configuration.

This is the Windows settings plane used by mainstream desktop browsers in their system-proxy mode. Mozilla documents **Use system proxy settings** as consuming the operating-system proxy configuration, and Mozilla support material for Windows describes it as following the Windows/IE LAN settings. Chromium documents that on Windows it uses the WinINET proxy configuration.

References:

- https://support.mozilla.org/en-US/kb/connection-settings-firefox
- https://support.mozilla.org/en-US/questions/1169706
- https://www.chromium.org/developers/design-documents/network-stack/proxy-settings-fallback/
- https://chromium.googlesource.com/playground/chromium-org-site/+/refs/heads/main/developers/design-documents/network-stack/debugging-net-proxy.md

## WinHTTP boundary

WinHTTP is a distinct Windows proxy stack and is intentionally not mutated by Proxy Launcher. This is an existing documented product boundary (`RELEASE_NOTES_0.2.2.md`), not an analogue of the Linux 0.2.6 Firefox bug. Browser system-proxy behavior is WinINET-based; services or applications that exclusively use WinHTTP may require separate future support.

## Regression evidence added

`tests/test_windows_system_proxy.py` now explicitly proves the successful enable path publishes the exact PAC URL to `AutoConfigURL`, sets `ProxyEnable=0`, updates the local HTTP proxy environment, retains recovery ownership, and calls the WinINET refresh seam.

## Conclusion

No Windows defect analogous to the Astra/Fly 0.2.6 issue was found. The Windows implementation already publishes to the settings plane consumed by Firefox/Chromium system-proxy mode, and the Linux 0.2.6 merge did not modify `windows_system_proxy.py`.

This audit does not claim that every Windows application automatically follows WinINET. WinHTTP-only and application-private proxy stacks remain separate compatibility classes.
