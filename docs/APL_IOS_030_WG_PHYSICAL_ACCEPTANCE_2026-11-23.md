# APL iOS 0.3.0 (49): physical WireGuard acceptance — 23 Nov 2026

This is the newest controlled test result; it supersedes the previous no-handshake test finding for the synthetic peer. It does not establish general UDP4/UDP6 operation or production peer availability.

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
- IPv4 DNS queries traversed the tunnel on UDP port 53; this does NOT establish arbitrary UDP4 or UDP6 datagram nonce acceptance. Independent UDP4/UDP6 challenge counters remain zero/unverified.

## Terminal device state and remaining gates

- Test VPN disconnected, OS PacketTunnel absent; temporary profile WireGuard-A9454208 deleted from library. Original WireGuard-8BFC7731 selected again; all three legacy proxy profiles preserved and legacy Основной selected on home screen.
- Test clipboard blanked; independent peer stopped, diagnostic listeners closed. No main merge, no App Store Connect upload or publication.
- Remaining: independent arbitrary UDP4/UDP6 witness or an explicitly deferred fail-closed capability; physical Wi-Fi/LTE handoff, security/provenance/licensing, wider AWG interop, VLESS production egress fail-closed and approved CloudKit two-device acceptance. Publish only after release acceptance.
