# APL iOS 0.3.0 — native IPv6 TUN and IPv6-only HTTPS using temporary upstream

Date: 2026-11-13 00:23–00:30 Moscow. iPhone13 / iOS27.2.1, signed Development Debug APL0.3.0(49), Mac mini QA LAN 192.168.1.80. This is controlled laboratory evidence, NOT a signed App Store release.

## Why this test was needed

All three original authenticated owner proxies passed IPv4-only HTTPS but failed three different IPv6-only HTTPS destinations (0/3 per destination). iPhone and Mac mini independently have direct native IPv6. APL's VirtualDNS can map IPv6-only hostnames onto synthetic IPv4 addresses, so success merely accessing an IPv6-only domain through a proxy is NOT proof of native IPv6 packet routing.

## Disposable upstream safety

The test-only Python script mobile/ios/Tools/qa_disposable_ipv6_connect_proxy.py exposes a LAN endpoint only by explicit invocation; default bind is loopback. A bounded process listened on 192.168.1.80:18081 and accepted only HTTPS CONNECT on port443 to three exact public IPv6-only echo hosts or the single public numeric IPv6 endpoint [2606:4700:4700::1111]. It uses Python AF_INET6 for upstream connections. All non-allowlisted hosts, all other ports, HTTP GET and generic proxy use are denied; concurrency and read timeouts are capped. No client IP, proxy secret, user profile, headers or contents logged. The process was stopped after tests, no persistent daemon or phone profile modifications.

Production PacketTunnel runtime was NOT patched. Existing signed Debug-only QA option qaSmart3ProxyHost=192.168.1.80 and qaSmart3ProxyPort=18081 (under qaStopAfterSeconds=25) selected a disposable no-credential HTTP upstream WITHOUT touching the three saved user profiles. Host app had independent 20s stop. Ordinary App Store config cannot select this route.

## Real signed iPhone results

1. Direct iPhone URLSession to v6.ident.me returned HTTPS200 + syntactically valid public IPv6. The temporary lab HTTP CONNECT proxy independently returned HTTPS200 + a different public IPv6. The same site via ACTIVE PacketTunnel returned HTTPS200 + public IPv6 matching the lab proxy, different from direct iPhone. VPN OFF restored the exact initial direct IPv6. **Physical XCTest PASS 2.181s**.
2. Mac mini preflight to public numeric IPv6 Cloudflare [2606:4700:4700::1111]:443 using explicit TLS SNI one.one.one.one with system certificate validation returned HTTP/1.1 200. The same fixed endpoint via temporary allowlisted HTTP CONNECT proxy returned validated TLS/HTTP200.
3. Signed iPhone used Network.NWConnection to the literal IPv6 address, NWProtocolTLS.Options with TLS server name one.one.one.one, no trust bypass; direct physical IPv6 TCP/TLS HTTP200 PASS before VPN. Under ACTIVE PacketTunnel, a new native IPv6 packet connection returned HTTP200. The local proxy independently recorded a permitted numeric IPv6 CONNECT from the device; this is **not** a VirtualDNS fake IPv4 DNS-name flow. After explicit VPN OFF, direct IPv6 SNI/TLS HTTP200 was restored. **Physical XCTest PASS 2.203s**.
4. Both tests used independent host stop at 20s and PacketTunnel extension auto-kill at 25s, explicit stop and deferred stop. On device all completed much earlier. After final test an independently signed NETunnelProviderManager read-only XCTest confirmed VPN OFF. Protected CoreDevice snapshot proves all three original profiles.v1 bytes and selected_profile_id EXACTLY match the original post-install snapshot. No profile/Keychain mutation, no IP or credentials printed.

## Acceptance scope

- [x] Real iPhone PacketTunnel can access IPv6-only HTTPS destinations through a verified IPv6-capable proxy.
- [x] Real iPhone PacketTunnel forwards an ORIGINAL numeric IPv6 destination packet through tun2proxy and the allowlisted IPv6 upstream, with validated TLS hostname and HTTP200.
- [x] Independent VPN OFF/profile preservation, no residual temporary proxy process, no permanent Mac mini network changes.
- [x] Signed iPhone Debug test build PASS, unsigned iPhoneOS Release App+PacketTunnel ARM64 build PASS, Python340/340 +1513 subtests, Swift226/226 PASS.
- [ ] The user's three existing commercial proxies still do NOT have confirmed IPv6 destination access. They were not changed. This lab proves application capability, not that any user-selected provider can access IPv6.
- [ ] Comprehensive DNS leak/fail-closed, UDP/QUIC, Wi-Fi/LTE transitions, background reconnect and live VLESS/Reality/WG/AWG/CloudKit/secure standalone backup are not yet accepted. One public iOS 0.3.0 release remains gated.

All raw XCTest logs, protected settings snapshots and the disposable proxy runtime remain only on Mac mini. Source-only QA tests and report can be kept in Git without private values.
