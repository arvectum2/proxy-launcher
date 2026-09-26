# APL-MAC-APPSTORE-001 — Mac App Store distribution lane

Status: submitted to App Review / Waiting for Review (0.2.17 build 1).

The existing direct-download macOS product remains a PyInstaller application signed with Developer ID and notarized by Apple. That lane is unchanged and continues to use bundle identifier `ru.arvectum.proxylauncher`.

Mac App Store distribution is a separate Mac Catalyst application using bundle identifier `ru.arvectum.proxylauncher.macos` and an embedded Packet Tunnel extension `ru.arvectum.proxylauncher.macos.PacketTunnel`. It reuses the native Swift/NetworkExtension implementation already used by the iOS App Store product instead of invoking `/usr/sbin/networksetup`.

## Why a separate lane is required

Mac App Store applications must use App Sandbox. A physical Mac mini smoke test on 2026-09-25 signed a minimal launcher with `com.apple.security.app-sandbox` and network client/server entitlements, then attempted `/usr/sbin/networksetup -listallnetworkservices`. The unsandboxed baseline succeeded; the sandboxed process exited with code 133 before returning network services. Therefore the existing `macos_backend.py` system-proxy mutation path is not an App Store-compatible backend.

Network Extension provides the store-compatible ownership boundary. The Catalyst target embeds `NEPacketTunnelProvider`, keeps proxy credentials in the Keychain, persists non-secret profile state in its own App Group, and routes traffic through the pinned tun2proxy engine.

## Isolation contract

- Developer ID/notarized direct distribution stays unchanged.
- Mac App Store bundle IDs, App Group, provisioning profiles and App Store Connect record are distinct from both the direct macOS bundle and the submitted iOS bundle.
- The App Store target must carry App Sandbox and Packet Tunnel Network Extension entitlements.
- The Store target must not import or invoke `macos_backend.py`, `networksetup`, LaunchAgent autostart, or the Developer ID signing/notarization scripts.
- `tun2proxy` remains pinned to v0.8.3 / source commit `e271de19683937f23d3f8f0eb4df0a61fc4a6e50` and is rebuilt for `aarch64-apple-ios-macabi` with the same live-restart forced-exit patch used by the iOS Network Extension.

## Release identity

Initial Mac App Store product version: `0.2.17`, build `1`.

Planned identifiers:
- app: `ru.arvectum.proxylauncher.macos`
- extension: `ru.arvectum.proxylauncher.macos.PacketTunnel`
- App Group: `VML75VY94V.ru.arvectum.proxylauncher.macos`
- shared Keychain suffix: `ru.arvectum.proxylauncher.macos.shared`

Mac App Store validation/upload uses the canonical local `Arvectum Release Bot` App Store Connect API credential. Private signing keys and provisioning profiles remain local and are never committed.

## First submission evidence

Apple Distribution archive/export PASS; Apple package validation/upload PASS; build 1 VALID / APP_STORE_ELIGIBLE; App Privacy Published / Data Not Collected; 175-territory availability; Mac screenshots COMPLETE; offline Help physical acceptance PASS; Packet Tunnel E2E physical acceptance PASS; version 0.2.17 build 1 submitted on 2026-09-26 and WAITING FOR REVIEW.
