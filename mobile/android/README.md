# APL-MOB-001 Android dogfood client

This directory is an isolated native Android implementation for the Mobile MVP. It does not alter the current Windows runtime.

## Product contract

The user-facing flow stays intentionally small:

1. enter proxy address and port;
2. optionally enter username/password;
3. select `SOCKS5` or `HTTP`;
4. press `ВКЛ`;
5. approve Android's VPN permission once;
6. press `ВЫКЛ` to disconnect.

No Clash/sing-box profiles, YAML/JSON, subscriptions, GeoIP or routing terminology are exposed in the UI.

## Current implementation

- native Android app and `VpnService`;
- real full-device TUN routing for IPv4 and IPv6;
- `tun2proxy v0.8.3` as the first dogfood engine, isolated behind `ProxyEngineAdapter`;
- SOCKS5 upstream proxies;
- HTTP CONNECT upstream proxies;
- username/password authentication;
- virtual DNS through the tunnel to avoid ordinary DNS leakage and to make domain access work with TCP-only HTTP proxies;
- one-button connect/disconnect lifecycle;
- foreground VPN notification;
- one persisted active proxy profile (storage layout is profile-ID scoped so multiple profiles can be added without changing the model);
- Android Keystore AES-GCM protection for the persisted proxy password;
- no plaintext credentials in config files or logs;
- explicit engine/package bypass to prevent the proxy's own sockets looping into the VPN.

## Engine choice

The first dogfood build uses [tun2proxy](https://github.com/tun2proxy/tun2proxy) rather than sing-box.

Reasons:
- MIT license instead of coupling the application to a GPL engine;
- supports both HTTP and SOCKS5, matching the MVP scope;
- Android and iOS support, so the same engine boundary can be evaluated on both mobile platforms;
- small TUN-to-proxy responsibility rather than an end-user configuration platform.

The engine is pinned to `v0.8.3`. CI verifies the official `tun2proxy-android-libs.zip` SHA-256 before packaging it. See `THIRD_PARTY_NOTICES.md`.

### HTTP limitation

A normal HTTP CONNECT proxy is fundamentally TCP-oriented. Web browsing and most ordinary TCP apps should work; arbitrary UDP traffic is not guaranteed through an HTTP upstream. SOCKS5 is the better option when the proxy server supports UDP and the application needs it. DNS itself is handled by tun2proxy's virtual DNS mode.

## Build

Fetch the pinned native library first:

```bash
python3 mobile/android/tools/fetch_tun2proxy.py
gradle -p mobile/android assembleDebug
```

GitHub Actions performs both steps and publishes the resulting debug APK as a workflow artifact.

## Dogfood checks still required on a physical phone

- install the debug APK;
- enter a real SOCKS5 proxy and verify a browser's public IP changes;
- repeat with the real HTTP proxy used by Proxy Launcher desktop;
- confirm ordinary apps have network access;
- test wrong credentials;
- test sleep/wake;
- test Wi-Fi → cellular → Wi-Fi;
- measure latency/throughput against SFA/Hiddify and direct connection;
- verify disconnect fully restores ordinary networking;
- inspect logs/files to confirm credentials are absent.

`SUPPORTS_ALWAYS_ON` is deliberately disabled for this dogfood slice until lifecycle/reconnect behavior is proven on a physical device.
