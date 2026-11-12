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
