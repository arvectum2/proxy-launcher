# APL iOS 0.3.0 — two alternate IPv6-only HTTPS targets, owner proxy preflight

Date: 2026-11-12 ~23:37 MSK. Real iPhone13 (iOS27.2.1), signed Debug APL0.3.0(49), three unchanged user saved authenticated proxies.

## Read-only methodology

DNS preflight on Mac mini found zero A and at least one AAAA record for each public host v6.ident.me and ipv6.icanhazip.com. The signed app-hosted physical XCTest first requires existing APL NetworkExtension OFF, verifies each public HTTPS IPv6 echo directly, then tries both endpoints through all three existing saved proxies via Network.ProxyConfiguration in ephemeral URLSession with allowFailover=false and original credentials read from iOS Keychain. No system VPN activation or preference mutation. No public IP, proxy host, UUID, username or password printed or persisted in QA telemetry. Anonymous profile indices and aggregate booleans only.

## Physical result

| IPv6-only HTTPS echo | Direct iPhone | Authenticated Apple per-session proxy |
|---|---|---|
| v6.ident.me | PASS, valid IPv6 | 0 / 3 |
| ipv6.icanhazip.com | PASS, valid IPv6 | 0 / 3 |
| api6.ipify.org (earlier hardware evidence) | PASS, valid IPv6 | 0 / 3 |

Physical XCTest PASS in 3.919 seconds (a diagnostics test; zero upstream successes is not marked an app defect). With the available original three proxy profiles, upstream reachability to the selected IPv6-only HTTPS services has NOT been established. These observations do not prove that all IPv6 destinations worldwide are unreachable; they establish a practical blocker for a meaningful PacketTunnel IPv6 end-to-end acceptance over the three tested profiles.

The previous literal IPv6 address HTTPS test under PacketTunnel returned TLS -1200, which cannot by itself distinguish path availability from certificate name/trust. IPv4-only host through PacketTunnel returned HTTP200 and native Rust CONNECT code0 on three later signed runs, though earlier -1001 failures were seen; no permanent route fix was made.

## Acceptance implication

- [x] Existing three authenticated profiles exercised read-only with no direct failover and anonymous counters.
- [x] Two independent alternative IPv6-only public sites directly reachable from iPhone, but unreachable via all three proxies in tested sessions.
- [ ] Obtain or provision a disposable proxy with independently verified IPv6 destination connectivity. Then compare direct and proxied hostname-valid TLS, before attempting 20s/25s bounded PacketTunnel IPv6 egress QA.
- [ ] DNS leak, UDP/QUIC, Wi-Fi/LTE fail-closed, native VLESS/WG/AWG and CloudKit/backup gates remain open.

Latest local checks: Python335/335 +1513 subtests; Swift226/226 PASS. Simulator physical-only alternate IPv6 QA skipped once, 0 failures, TEST SUCCEEDED. Independent signed NetworkExtension check after test confirmed VPN OFF and App Group profile bytes/selected ID match protected original.

No App Store release or user VPN setting changes authorized by these tests.
