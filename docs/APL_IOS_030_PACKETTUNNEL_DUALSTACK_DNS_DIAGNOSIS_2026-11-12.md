# APL iOS 0.3.0: PacketTunnel dual-stack and VirtualDNS hardware diagnosis

Date: 2026-11-12. Owner iPhone13, iOS27.2.1, signed Development Debug APL0.3.0(49); existing 3 proxies and Keychain credentials preserved.

All physical active QA methods are in the separate Xcode ArvectumKeychainReadOnlyQA scheme, gated with APL_RUN_EXPLICIT_VPN_QA; simulator skips them. Before each active QA, a signed NetworkExtension status probe confirms OFF. The host arms a 20-second stop and the PacketTunnel independently enforces qaStopAfterSeconds=25. Neither scheme writes user proxy profiles nor reads out passwords, IP values or profile UUIDs in the logs. After each attempt an independent signed OFF test and App Group preference snapshot were compared with the saved post-install baseline.

## Observations

| Path | IPv4-only HTTPS | IPv6-only HTTPS | Evidence |
|---|---|---|---|
| iPhone direct, VPN OFF | PASS, valid IPv4 | PASS, valid IPv6 | Physical read-only baseline |
| Apple ephemeral authenticated proxy, VPN OFF, three saved profiles | 3/3 PASS to ipv4.icanhazip.com | 0/3 to api6.ipify.org | Per-session Apple ProxyConfiguration allowFailover=false |
| Real PacketTunnel, same hostname endpoints | HTTPS timeout -1001 | HTTPS timeout -1001 | Two bounded hardware QA experiments; PacketTunnel Connected, restored OFF |
| Real PacketTunnel, public literal Cloudflare IP | IPv4 1.1.1.1 TLS/HTTPS HTTP200 PASS and external source changed | IPv6 [2606:4700:4700::1111] TLS error -1200 | A literal-IP TLS failure cannot establish IPv6 transport failure |
| After explicit PacketTunnel OFF | Direct source restored | Direct source restored | In-process source comparison and independent OFF probe |

Prior ordinary PacketTunnel HTTPS tests confirmed both public IP witnesses changed on VPN connection and restored on disconnect, 2/2, so the system VPN is not generically inoperative.

The initial combined family test failed. Separated IPv4-only and IPv6-only requests each timed out with -1001. In the numeric-IP experiment the IPv4 HTTPS request succeeded; the literal IPv6 address returned -1200 on TLS validation. The xcodebuild host process sometimes lingered after XCTest completed and was limited by an external timeout; do not classify that as a separate networking bug.

## Real DNS snapshot on physical iPhone

Signed test testBoundedAPLPacketTunnelDNSSyntheticAddressDiagnosis PASS in 2.004 seconds. Only family counts, synthetic count, and status were printed (no DNS answers).

| Public hostname | APL VPN OFF | APL VPN ON |
|---|---|---|
| ipv4.icanhazip.com | 2 A, 0 AAAA, 0 synthetic | 1 A, 0 AAAA, 1 synthetic |
| httpbingo.org | 1 A, 1 AAAA, 0 synthetic | 1 A, 0 AAAA, 1 synthetic |

Both getaddrinfo calls returned code 0. The synthetic IPv4 belongs to tun2proxy's intended 198.18/15 VirtualDNS range. Therefore a general DNS-resolution outage is NOT proven. The remaining IPv4-only failure occurs after a synthetic address was obtained and requires investigation of fake IP to hostname mapping, target-proxy CONNECT, and TLS traffic in Rust tun2proxy.

Latest local full test suite: Python331/331 +1513 subtests; Swift226/226 PASS. Separate signed OFF test after DNS snapshot PASS; App Group profiles.v1 exact bytes and selected_profile_id unchanged relative to the original protected post-install snapshot.

## Remaining blocking acceptance checks

- [ ] IPv4-only hostname HTTPS over PacketTunnel not confirmed even though IPv4 numeric HTTPS and Apple per-session-proxy reachability both pass.
- [ ] Real IPv6 over PacketTunnel needs a hostname-valid TLS endpoint reachable from the proxy. IPv6-only api6 endpoint failed via all three saved proxies; numeric TLS -1200 does not prove a broken route.
- [ ] DNS leak, UDP/QUIC, Wi-Fi/LTE, fault-induced fail-closed, native VLESS/WG/AmneziaWG, CloudKit and full encrypted standalone backup are not accepted.
- [ ] One public App Store iOS 0.3.0 release remains gated and no submission has occurred.

Next isolate one IPv4-only flow through synthetic DNS address to original host to authenticated CONNECT/SOCKS5 to TLS, recording only anonymous phases and error codes. Compare identical existing proxy via Apple per-session transport (already 3/3 PASS) to Rust tun2proxy. Only after source-level cause is established, implement a minimal pinned Rust patch, unit tests, reproducible framework build and bounded physical acceptance. No speculative DIRECT fallback; preserve owner data and existing VPN.
