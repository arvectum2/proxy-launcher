# APL iOS 0.3.0 — WireGuard/AmneziaWG compatibility gate

**State (2026-11-12): source-only preview, no running WireGuard backend and no production VPN protocol enabled.** This is a stage of the *single* iOS 0.3.0 release, not a separate public version.

## Implemented

- A pure, fail-closed `WGQuickConfigurationPreview` for a bounded wg-quick subset: maximum 16 KiB / 160 lines, one `[Interface]`, up to eight `[Peer]` sections.
- Validates 32-byte base64 Curve25519 key *syntax* (does **not** import or persist key material); addresses, DNS entries, IPv4/IPv6 prefix lengths, peer endpoint host/port, keepalive, MTU, and supported section keys.
- Explicitly rejects shell hooks (`PostUp`, etc.), duplicate fields, invalid CIDR/keys, unknown transport parameters, and configs containing AWG2/3 fields rather than silently downgrading to WireGuard.
- Recognizes only complete AmneziaWG v1 header obfuscation parameters `Jc/Jmin/Jmax/S1/S2/H1/H2/H3/H4` as a separate *preview format*; it is not a claim of compatible packet transport, app support or version negotiation.
- Returns **display-only** endpoint/allowed IPs and `hasPresharedKey`; never returns the private, peer public or preshared key bytes and never touches Keychain, NetworkExtension, UserDefaults or VPN.
- Historical `ProxyType` remains HTTP/HTTPS/SOCKS5; no WireGuard/AmneziaWG is shown as a selectable functional protocol in the app.

## Pending implementation and acceptance gates

- [ ] Review compatible source engines and transitive licenses (including WireGuardKit/Go/AmneziaWG), pin source SHA, legal notices, create reproducible iPhoneOS/SIM build and SBOM.
- [ ] Decide one safe strategy for current Rust `tun2proxy`, Xray Go runtime and WireGuard/AmneziaWG engine without two conflicting Go runtimes in a single PacketTunnel process; see `docs/APL_IOS_030_XRAY_RESEARCH_2026-11-11.md`.
- [ ] Design secure key import: explicit opt-in, secrets in protected Keychain, no plaintext URL/QR/log, profile identity and rollback preserved.
- [ ] Implement actual UDP handshake and tunnel routing in a separate lab configuration before exposing UI. Test DNS, IPv4, IPv6, keepalive, expiration, excluded sites, failover and network changes.
- [ ] Confirm independent real-server receipts on a *physical iPhone*. Syntax preview and Simulator builds are not evidence of transport.
- [ ] Add only fully tested transport variants to final signed iOS 0.3.0; unsupported formats stay inactive.

## Local acceptance record

- [x] 7 new WG/AWG1 Swift parser tests PASS.
- [x] 3 source-only Python gates PASS: protocol remains absent from production app and PacketTunnel, parser has no persistence/networks.
- [x] Full Swift 220/220 PASS, iOS source Python 298 + 1513 subtests PASS.
- [x] iOS ARM64 Simulator Debug App+PacketTunnel BUILD PASS, iPhoneOS Release App+PacketTunnel unsigned BUILD PASS.

## Обновление 12.11: единый Xray backend вместо второго Go-runtime

[Проверенная гипотеза объединения транспорта VLESS + standard WireGuard](APL_IOS_030_UNIFIED_XRAY_WG_ENGINE_2026-11-12.md): официальный `Xray-core` уже имеет `wireguard` outbound, а pinned `libXray v26.11.9` успешно выполняет синтетическую WireGuard config test → run → state → stop на ARM64 iOS Simulator без внешнего peer. Это упрощает дальнейшую архитектуру APL до одного нативного Go-движка плюс Rust `tun2proxy` для стандартного WG. **Проверки настоящего WireGuard handshake и AmneziaWG отсутствуют.** Не менять production `ProxyType` или активный туннель.

## 14.11.2026 — Actual standard WireGuard packet-chain lab PASS

The pinned libXray v26.11.9 macOS process accepted a real WireGuard
inbound; iOS27 ARM64 simulator client used the same pinned runtime
and corrected source-built Rust tun2proxy (simulator SHA256
5c41479cdb10066f23a17d2fe876ec1a4daec6f5b2e897a564bf49c077b5e00c).
Lab-only WGQuickConfigurationPreview and XrayWireGuardLabConfig
accept a strict synthetic one-peer subset with ephemeral private
and public keys and preshared key. AWG is explicitly rejected,
not silently downgraded. No real user profile or key used.

Actual private Darwin-framed synthetic TCP packet socketpair ->
Rust -> local SOCKS -> Xray WireGuard outbound -> loopback UDP relay
-> separate macOS native WireGuard inbound -> exact synthetic /32
receipt route -> independent local HTTP witness. Observed server
UDP listener 127.0.0.1:39882, relay 127.0.0.1:39881. No public
listener, DNS or default route. The relay counts message headers
only; it does not store payloads. Fresh one-command --wg run exit0.

| Case | Exact response | Witness count | Initiations | Handshake replies | Client transport packets | Server transport packets |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Valid including PSK | yes | 1 | 1 | 1 | 4 | 3 |
| Incorrect server public key | no | 0 | 2 | 0 | 0 | 6 |
| Incorrect PSK | no | 0 | 2 | 2 | 0 | 3 |
| Stopped peer | no | 0 | 2 | 0 | 0 | 0 |

All four Rust exit0, drain, caller FD close and Xray stop markers
verified. Negative phases can contain delayed packets from the
earlier peer session; do not interpret their header counts as
successful authentication. Exact unique HTTP receipt counts and
lack of a successful response are the negative-case oracle.
No actual NetworkExtension, independent non-Xray WG implementation,
IPv6, app UDP transport, physical radio/memory, external peer or AWG
acceptance claimed.

Reproduce: PYTHON=python3.14 mobile/ios/Tools/run_xray_vless_config_simulator_qa.sh
PINNED_ASSET PINNED_GO_MOD com.apple.CoreSimulator.SimRuntime.iOS-27-0 --wg
with verified corrected Rust archive. No production target changes.

14.11: [isolated AmneziaWG native source/build/packet gate](APL_IOS_030_AMNEZIAWG_NATIVE_LAB_2026-11-14.md) accepted for the measured matching legacy fixture on official v3.1.20260828 engine. Separate process, real loopback UDP, no system TUN. Fresh ARM64 macOS and iOS Simulator native PASS3/3; iPhoneOS link PASS. Product compatibility, separate signed extension, current-toolchain security/license clearance still pending.
