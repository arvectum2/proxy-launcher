# APL iOS 0.3.0 (49): physical WireGuard acceptance — 23 Nov 2026

This is the newest controlled test result; it supersedes the previous no-handshake test finding for the synthetic peer. Subsequent exact synthetic application-level UDP4/UDP6 receipts are now verified; this is not proof of arbitrary Internet egress or production peer availability.

## Exact source and build

- Source f23dffaf4252749852b6434989734e1ed50f9c21 (PR #383): owner-only safe re-enable of disabled iOS Native Product VPN manager; no owner bypass or cross-manager deletion.
- Signed native archive and dual IPA under private artifact ios-030-release-candidate-20261123-reenable-f23dffaf; native-ipa-verification.json confirms App/PacketTunnel signatures, arm64, correct profiles, Yandex ads retained.
- AppStore IPA SHA-256 4f9747d05118a4b2b796886c291e1e9fe6f2e22ffe00d1d3c01457741fd0ebff.
- Development IPA SHA-256 823c4a48aa284434c1600419aa2f6b9e9f66d9f01d6bf564d1621279d8d8e0c8.
- Swift 432/432, focused Python 14/14, exact source PR CI all green.

## iPhone 13 and independent wireguard-go evidence

- Development IPA installed in-place; three existing legacy profiles and original WG remained available. Switching legacy to native WG recovered disabled owner manager without deleting OS VPN record. Original WireGuard start/stop and PacketTunnel observed.
- Synthetic exact-key profile, pinned WireGuard reference peer and DNS-capable non-Xray netstack; local independent DNS/TCP4 positive control PASS. Diagnostic reference logs packet-type, IP-family, port and flags only, never payload or keys.
- Private artifact product-physical-wg-metadata-r6-20261123/result.json: valid MAC1 2/2, handshake response type2=2, bidirectional encrypted data, independent TCP4 HTTP challenge receipt 1; Safari displayed nonce receipt.
- Private artifact product-physical-wg-metadata-r7-20261123/result.json: valid MAC1 1/1, type2=1, encrypted c2s4=286/s2c4=86, independent TCP4 HTTP receipt 1, TCP6 HTTP receipt 1, exact DNS A answer 1. The iPhone Safari displayed the challenge receipt; independent server counted each protocol-family result.
- The earlier r7 run proved only IPv4 UDP port 53 DNS; it was not sufficient to claim general UDP4/UDP6. Separate r10 UDP nonce witnesses now establish both IP families for this synthetic profile.

## Final bounded UDP4/UDP6 end-to-end physical acceptance

- The first r8 test with a modified NativeLab app having its own VPN extension did NOT complete the server handshake (MAC1 29/29; no reply) and cannot be used to diagnose UDP. A subsequent APL-only r9 independent TCP4 control succeeded, isolating the false negative to the test setup.
- A separate standalone QA host without NetworkExtension permissions or embedded PacketTunnel was compiled as unsigned arm64, signed only against the existing approved development QA identity, temporarily installed in place of the existing HTTPSWitness QA app, and launched with exactly one bounded 40-character synthetic nonce. The exact tested Swift source and xcodegen project are now in mobile/ios/Tools/NativeUDPPhysicalProbe, not in production APL.
- Private product-physical-wg-udp-r10-standalone-20261123/standalone-client-result.json: matching runID, tcp4Control=true, udp4Reply=true, udp6Reply=true, each authenticated as exact APL_RECEIPT:<nonce>. No arbitrary hosts, production VPN credentials or user traffic were used.
- Independent private product-physical-wg-udp-r10-standalone-20261123/result.json: MAC1 valid 2/2, handshake type2=1, encrypted data c2s4=219 and s2c4=15, tcp4=2, udp4=1 and udp6=1 accepted synthetic exact-nonce receipts. The server and iPhone evidence independently agree; source iOS 0.3.0(49) f23dffaf unchanged.
- Synthetic peer was LAN-only (192.168.1.80 UDP underlay), full-tunnel fixture allowed both 0.0.0.0/0 and ::/0, synthetic DNS 192.0.2.53. This establishes controlled IPv4/IPv6 TCP and UDP path, not WAN/mobile handoff, global VPN leak resistance or a blanket release gate.

## Terminal device state and remaining gates

- After subsequent r10, OS PacketTunnel absent, test VPN off; temporary library profiles WireGuard-A9454208 and WireGuard-EBE7DECE deleted after their respective tests. Original WireGuard-8BFC7731 reselected and all three legacy proxy profiles preserved, legacy Основной selected on home screen.
- Test clipboard blanked; independent peer stopped, diagnostic ports closed. Original pre-existing signed HTTPSWitness and NativeLab QA apps restored after the standalone trial. Test client app result scrubbed from device. No main merge, no App Store Connect upload or publication.
- Remaining: physical Wi-Fi/LTE handoff, underlay/socket routing, kill-switch and DNS leak tests under network faults, security/provenance/licensing, wider AWG interop, VLESS production egress fail-closed and approved CloudKit two-device acceptance. Publish only after release acceptance.
