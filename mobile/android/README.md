# APL-MOB-001 Android dogfood client

This directory is an isolated native Android implementation for the Mobile MVP. It does not alter the desktop runtimes.

> Dogfood note (2026-09-18): 0.1.4 passed physical transport acceptance, 0.1.5 passed multiprofile acceptance, and 0.1.6 physically confirmed pool Auto switching. 0.1.7 keeps networking unchanged and refines Android UX/branding: Auto has no credential form, the screen follows the desktop Arvectum brand system, the primary control is a large round power button, and launcher branding uses Android adaptive-icon semantics rather than a pre-masked bitmap.

## Product contract

The user-facing flow stays intentionally small:

1. choose `Авто`, an existing saved proxy, or tap `НОВЫЙ`;
2. for a concrete profile, enter a profile name, address/port and optional username/password;
3. keep the default per-profile `Авто-протокол`, or force one transport for diagnostics;
4. save the profile or simply press `ВКЛ` (connect also saves it);
5. approve Android's VPN permission once;
6. while connected, choose another saved proxy (or pool-level `Авто`) and the app performs disconnect → switch → reconnect itself;
7. press `ВЫКЛ` to disconnect.

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
- multiple named proxy profiles with persisted manual or pool-level Auto selection;
- automatic migration of the pre-0.1.5 single active profile into the profile index;
- saved-profile selector remains active while connected and orchestrates disconnect → selection → reconnect;
- while connected, a new saved profile can be added to the pool without changing the live tunnel; editing/deleting existing profiles remains locked until disconnect;
- pool-level Auto probes saved profiles with bounded timeouts and connects through the first working candidate according to the documented primary/last-success/fallback policy;
- connected Auto continuously checks the active upstream, confirms failures with debounce, and hands off to a fresh isolated VPN process for automatic fallback without requesting VPN permission again;
- saved profiles expose bounded health state and probe latency in the existing profile chooser; latency is a connection-health signal, not a throughput guarantee;
- Auto can either stay on the working fallback or return to the designated primary after recovery, with cooldown/hysteresis to avoid flapping;
- a bounded credential-free Auto event log records unavailable/switch/restored decisions;
- Auto status names the saved profile and resolved transport selected for the tunnel;
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

Android follows the same desktop brand tokens used by `proxy_gui.py`:

- Deep Navy `#001432`;
- Mint Primary `#00C8A0`;
- Mint Light `#78FAE6`;
- Soft Gray `#C8D2DC`;
- Graphite `#283246`;
- white surfaces.

The Android launcher icon is derived at build time from the canonical source
`assets/arvectum-icon-0.2.2-transparent.png`, but Android owns the outer mask. 0.1.7 uses adaptive-icon resources with a full Deep Navy background and an expanded/padded foreground safe area. This avoids the 0.1.6 double-mask effect where a pre-circular bitmap looked too small and clipped AV/globe details. Desktop/iOS branding is unchanged.

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


## 0.1.6 Auto/switch dogfood gate

0.1.6 intentionally covers the first practical APL-MOB-002 behavior, not the full long-running failover roadmap.

- install over 0.1.5 without uninstalling;
- while connected to profile A, choose profile B and confirm the app disconnects/reconnects by itself without another VPN permission prompt;
- choose pool-level `Авто`, connect, and confirm it skips an unavailable saved proxy and selects a working one;
- confirm connected status names the actual profile chosen by Auto;
- confirm profile editing/deletion remains locked while connected even though the profile selector itself stays enabled;
- confirm the launcher icon is circular on Android.

Continuous background health monitoring/failover after an already-connected upstream later dies remains a later APL-MOB-002 slice; 0.1.6 Auto chooses a working upstream during connect/reconnect.


## 0.1.7 UX/branding refinement

- selecting pool-level `Авто` hides the entire host/port/login/password/protocol editor; those fields exist only for `Новый прокси` and concrete named profiles;
- the status card, section hierarchy, mint/navy actions and typography mirror the desktop Arvectum visual system;
- the primary connect/disconnect action is a 156dp circular brand button: Mint/Navy for connect and Deep Navy/White for disconnect, with Android ripple feedback;
- profile selection remains available while connected for hot-switch, while editing/New/Save/Delete remain locked;
- stable dogfood signing identity is unchanged.


## 0.1.8 UI/UX contract

The Auto home is intentionally non-scrollable and contains only:

- compact Arvectum header/version;
- one large circular state control;
- one concise profile/transport status line;
- clearly affordant profile dropdown with chevron;
- New/Edit secondary actions.

There is no Auto help card and no credential form on the home screen.

Proxy fields exist only inside the focused New/Edit dialog for a concrete profile. Connected profile hot-switch and pool Auto behavior remain unchanged from the accepted 0.1.6 networking implementation.

Design specification: `docs/mobile/APL_MOB_002_ANDROID_UI_UX_0_1_8_SPEC.md`  
Seven-pass review log: `docs/mobile/APL_MOB_002_ANDROID_UI_UX_0_1_8_REVIEW.md`


## 0.1.9 physical-UX correction

0.1.9 keeps the accepted 0.1.8 one-screen layout and networking behavior, and corrects three device-observed details:

- the central state label is always one line and auto-sizes to fit the circular control;
- the profile chooser is a branded single-choice radio popup rather than square menu checkmarks;
- launcher branding returns to a true adaptive icon: Deep Navy is the full-bleed Android background layer, while the canonical source artwork is the unpadded foreground. This prevents an OEM white outer ring.

No Auto/hot-switch/tunnel behavior changes are part of 0.1.9.


## 0.1.10 visual branding correction

0.1.10 keeps the accepted 0.1.9 one-screen UI and networking behavior, and makes two owner-requested visual corrections:

- the adaptive icon keeps the full-bleed Deep Navy background but scales the canonical foreground to 68% of the adaptive canvas so the complete squircle/AV/globe survives circular OEM masks without clipping;
- the main header uses the canonical `assets/arvectum-wordmark.png` resource followed by `Proxy Launcher`; the subtitle is reduced to `Android · <version>`.

No tunnel, Auto-selection, hot-switch or profile-storage behavior changes are part of 0.1.10.


## 0.1.11 residual visual polish

0.1.11 keeps the accepted networking and one-screen home behavior and corrects four target-device details observed in 0.1.10:

- `Proxy Launcher` is reduced to 18sp and balanced against a slightly wider canonical Arvectum wordmark presentation;
- adaptive launcher foreground is reduced from 68% to 60% of the canvas while the Deep Navy adaptive background remains full-bleed, keeping the complete canonical logo inside circular OEM masks;
- New/Edit profile dialog no longer uses a scrolling field container: field heights/margins/title/actions are compacted and the window uses `wrap_content` so all fields and actions fit at once on the target phone;
- connection-state button labels are shortened to `Подключение`, `Отключение`, and `Переключение` without ellipses while remaining single-line/autosized.

No tunnel, Auto-selection, hot-switch or profile-storage behavior changes are part of 0.1.11.


## 0.1.12 visual cleanup

0.1.12 keeps the accepted connection/profile behavior and makes the final visual cleanup from physical 0.1.11 review:

- launcher foreground is rebuilt from the clean canonical AV mark plus the circular globe badge; the desktop squircle background is no longer embedded, so square/squircle seam lines cannot appear inside the Android circle;
- the header uses the canonical AV mark followed by a single Android-rendered `Arvectum Proxy Launcher` text run, giving Arvectum and Proxy Launcher identical font, weight, size and baseline;
- the visible subtitle is the semantic version only;
- Android `versionName` is `0.1.12` (no `dogfood` suffix);
- home connection detail simplifies `HTTP/HTTPS (CONNECT)` to `HTTP/HTTPS` and removes transient “Создаём VPN…” wording.

The design review explicitly recommends adding no further controls to the home screen in this slice.


## 0.1.13 launcher/header correction

- launcher returns to the visually accepted 0.1.11 60%-centered geometry;
- before scaling, all desktop squircle/background pixels are stripped to transparent;
- only Mint AV artwork plus the complete globe badge remain above the full-bleed Deep Navy adaptive background;
- header is one bottom-aligned row: AV mark · Arvectum Proxy Launcher · 0.1.13 at the far right.

Networking and profile behavior are unchanged.

## 0.1.14 continuous Auto failover

0.1.14 completes the remaining Android APL-MOB-002 pool behavior while preserving the accepted 0.1.13 home screen.

- **Primary and backups:** one saved profile is designated primary; every other saved profile is an eligible backup.
- **Auto order:** primary first, then the last successful Auto profile, then the remaining saved profiles. A recently failed profile is temporarily pushed to the end of the list.
- **Health:** while Auto is connected, the active upstream is probed on a bounded interval. Saved-profile health and successful probe latency are shown only inside the existing profile chooser. The latency value is not a bandwidth or throughput estimate.
- **Failure confirmation:** three consecutive health failures are required before automatic failover. A switch cooldown and recently-failed suppression window prevent rapid oscillation.
- **Process-safe switching:** tun2proxy is not restarted inside the same `:vpn` process. The failing process closes its TUN, persists failover state, remains a started `START_STICKY` VPN service, and terminates only the isolated process. Android then recreates the sticky service in a fresh `:vpn` process; the existing VPN grant is reused rather than requested again.
- **Primary recovery:** the user can keep the current working fallback (default) or automatically return to primary after it is healthy again and cooldown has elapsed.
- **Network transitions:** default-network changes add a settle grace before health failures count, reducing false switches during Wi-Fi/cellular transitions. The periodic monitor naturally resumes after sleep/wake.
- **No working proxy:** the old tunnel is closed before fallback probing; if every candidate fails, the app reports an explicit error and leaves no ambiguous active TUN.
- **Process boundary:** live health/event telemetry is relayed into a separate default-process preference store so the UI never relies on unsupported cross-process `SharedPreferences` cache coherence. Failover-critical state is committed before the old `:vpn` process terminates and is read by the fresh sticky-restarted `:vpn` process.
- **Events:** Auto records only timestamp, event type, profile id/name and fixed non-secret detail. Host, username, password and proxy authorization are never written to the event log.

Physical acceptance for this slice must kill the active Auto-selected test proxy and confirm automatic fallback plus Internet recovery without another VPN permission prompt. A short transient outage must not create repeated switching.

## 0.1.15 connected profile-create fix

0.1.15 is a dogfood follow-up to the 0.1.14 physical pass.

- `+ Новый` stays available while VPN state is `CONNECTED`.
- Saving a new profile while connected adds it to storage only; it does not change the active profile, live tunnel, primary designation, or visible connection state. The new profile becomes eligible for the next reconnect/fresh VPN process.
- Editing/deleting an existing profile remains locked while connected.
- The Auto event entry/dialog is renamed from `События Auto` to `Журнал`.
- `versionCode` advances to 16 so the physical test device can update in place from the already-installed 0.1.14 candidate.

## 0.1.16 default-network migration fix

0.1.16 follows the physical Wi-Fi → hotspot failure found on 0.1.14 while preserving the 0.1.15 connected-profile-create and Journal fixes.

- The dedicated `:vpn` process explicitly binds its future Java/native sockets and DNS to Android's newly active default `Network` with `ConnectivityManager.bindProcessToNetwork(...)`; `VpnService.setUnderlyingNetworks(...)` reports the same physical carrier to Android.
- Losing the current underlying network clears both bindings; the next `onAvailable` adopts the replacement network.
- `onCapabilitiesChanged` re-asserts the current binding when Internet capability is present, but no longer resets the network-settle timer. This prevents validation/capability churn from extending failover suppression indefinitely.
- A real default-network identity change resets accumulated Auto health failures so failures observed on the old Wi-Fi do not count against the replacement hotspot.
- The credential-free Journal records a `смена сети` event when a replacement default network is adopted.
- Manual-profile VPN sessions also register the default-network callback so the migration behavior is not limited to pool Auto.
- Auto health checks keep the existing settle grace after a real network identity transition before counting failures.
- Android version is `0.1.16` / versionCode 17 for an in-place update over 0.1.15 and earlier stable-signed dogfood builds.

## 0.1.17 physical-network handoff fix

0.1.17 replaces the 0.1.16 default-network-only callback after physical testing on a Realme/Oppo device showed that Wi-Fi → hotspot was not reported there: traffic stopped, UI stayed Connected, and no network-change Journal event was emitted.

- Network observation now subscribes to all physical `INTERNET + NOT_VPN` networks instead of relying only on `registerDefaultNetworkCallback`.
- The service reconciles the app-visible active physical network first, then validated non-VPN candidates, while avoiding a switch just because multiple physical networks coexist.
- When the physical carrier identity actually changes, the app records credential-free `смена сети`, reports a reconnecting state, closes the old TUN/native engine, and sticky-restarts only the isolated `:vpn` process.
- Network handoff does **not** mark the proxy unavailable, does not set `recentlyFailed`, and does not advance the proxy failover cooldown. It is transport recovery, not proxy failover.
- The fresh `:vpn` process runs normal preflight and recreates tun2proxy sockets on the replacement Wi-Fi/hotspot/cellular carrier while reusing the already-granted Android VPN permission.
- Existing Auto proxy-failure failover, anti-flapping, connected `+ Новый`, and `Журнал` behavior remain unchanged.
- Android version is `0.1.17` / versionCode 18.
