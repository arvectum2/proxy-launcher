# APL-MOB-001 Android dogfood client

This directory is an isolated native Android implementation for the Mobile MVP. It does not alter the desktop runtimes.

> Dogfood note (2026-09-18): 0.1.4 passed physical end-to-end acceptance for HTTP CONNECT, public-IP routing, repeated OFF/ON and sleep/wake. 0.1.5 keeps that tunnel path unchanged and adds the next MVP slice: multiple securely stored named proxy profiles plus manual active-profile selection.

## Product contract

The user-facing flow stays intentionally small:

1. choose an existing saved proxy or tap `НОВЫЙ`;
2. enter a profile name, address/port and optional username/password;
3. keep the default `Авто: HTTP/HTTPS → SOCKS5 → HTTPS-proxy (TLS)`, or force one transport for diagnostics;
4. save the profile or simply press `ВКЛ` (connect also saves it);
5. approve Android's VPN permission once;
6. press `ВЫКЛ` to disconnect.

In Auto mode the same endpoint and credentials are reused across HTTP CONNECT, SOCKS5 and TLS-to-proxy HTTPS probes. The user does not duplicate settings per protocol.

No Clash/sing-box profiles, YAML/JSON, subscriptions, GeoIP or routing terminology are exposed in the UI.

## Current implementation

- native Android app and `VpnService`;
- VPN/native engine runs in the dedicated `:vpn` process, isolating the UI from native-engine exits;
- real full-device TUN routing for IPv4 and IPv6;
- `tun2proxy v0.8.3` behind `ProxyEngineAdapter`;
- `--ipv6-enabled` is explicitly passed to the engine because IPv6 is routed into TUN;
- SOCKS5 upstream proxies;
- HTTP CONNECT upstream proxies;
- HTTPS proxies (TLS transport to the upstream proxy) through a local TLS relay;
- Auto transport probing: HTTP CONNECT → SOCKS5 → TLS-to-proxy HTTPS using one credential set;
- bounded connect/read/TLS-handshake timeouts with per-candidate progress;
- preflight CONNECT/authentication diagnostics before Android reports a connected VPN;
- username/password authentication;
- virtual DNS through the tunnel;
- one-button connect/disconnect lifecycle;
- foreground VPN notification;
- multiple named proxy profiles with manual active-profile selection;
- automatic migration of the pre-0.1.5 single active profile into the profile index;
- create/edit/save/delete profile controls are locked while the tunnel is connecting/connected/disconnecting;
- Android Keystore AES-GCM protection for each persisted proxy password;
- no plaintext credentials in config files or logs.

## Why the VPN process is separate

The pinned tun2proxy Android JNI path currently uses a generic shutdown safeguard which calls `process::exit(-1)` shortly after its native runtime returns. That behavior is appropriate to a standalone process but not to an Android UI process.

The dogfood client therefore hosts tun2proxy in `:vpn`. Disconnect kills/recreates only that process; the application UI remains alive. This is also useful crash containment for any future native engine.

## HTTP and HTTPS terminology

`HTTP/HTTPS proxy (CONNECT)` is the normal system-proxy-compatible path for HTTPS destination traffic: the phone opens a plain TCP connection to the proxy and asks it to create a tunnel with HTTP `CONNECT`.

`HTTPS-proxy (TLS)` means the phone first establishes TLS to the proxy server itself and then sends the HTTP CONNECT protocol inside that encrypted channel.

These are different concepts. A desktop field named “HTTPS proxy” often still points to an ordinary HTTP CONNECT proxy rather than a TLS-wrapped proxy endpoint. Auto mode intentionally tries HTTP CONNECT first.

## Dogfood signing and upgrades

Starting with `0.1.2-dogfood`, debug/dogfood APKs use the repository-pinned non-production signing key at
`mobile/android/signing/proxy-launcher-dogfood.keystore`.

Certificate SHA-256 fingerprint:

`FD:57:CD:46:AD:1E:54:A1:53:AA:9E:D5:6B:4B:BB:63:0B:33:01:5E:23:D4:C6:A8:60:77:A6:7C:F0:E2:83:13`

The key is intentionally a public dogfood/debug identity and must never be reused for Play/RuStore/production distribution.

The first two CI dogfood builds were signed by ephemeral runner debug keys. Android therefore cannot update an already-installed
pre-0.1.2 dogfood APK to the stable signer without the old private key. **One uninstall is required when moving to 0.1.2.**
After 0.1.2 is installed, later dogfood APKs signed with this key can update it in place as long as versionCode increases.

## Branding

The Android launcher icon is generated from the same canonical source used for the desktop product family:
`assets/arvectum-icon-0.2.2-transparent.png`.

## Build

Fetch the pinned native library first:

```bash
python3 mobile/android/tools/fetch_tun2proxy.py
gradle -p mobile/android assembleDebug
```

GitHub Actions performs both steps and publishes the resulting debug APK as a workflow artifact.

## Physical dogfood acceptance

0.1.4-dogfood passed on the owner's Android test device and is the transport baseline for 0.1.5:

- in-place update from the stable-signed dogfood line;
- Auto selected HTTP/HTTPS (CONNECT);
- browser traffic reached the Internet through the configured upstream proxy;
- public IP changed to the proxy exit while connected and returned to the ordinary Wi-Fi address when disconnected;
- repeated OFF → ON worked;
- sleep/wake worked.

Wi-Fi ↔ cellular remains deferred because the current test device has no SIM. It is not treated as a failure of this acceptance slice.

Further robustness checks remain useful for later slices: wrong credentials/unavailable proxy, Wi-Fi-to-Wi-Fi or hotspot transitions, cellular transition on a SIM/eSIM device, and longer-running battery/reconnect behavior.

`SUPPORTS_ALWAYS_ON` remains disabled until reconnect/network-transition behavior is proven more broadly.


## 0.1.5 multiprofile dogfood gate

The next physical check is intentionally small:

- install 0.1.5 over 0.1.4 without uninstalling;
- confirm the existing 0.1.4 proxy appears automatically as a saved profile;
- save a second named proxy profile;
- switch between the two saved profiles while disconnected;
- connect through each profile and confirm the selected endpoint is the one used;
- confirm profile New/Save/Delete controls are disabled while the VPN is active.
