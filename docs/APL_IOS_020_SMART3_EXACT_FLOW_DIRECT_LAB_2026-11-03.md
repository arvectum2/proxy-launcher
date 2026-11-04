# iOS 0.2.0 — Smart3 exact-host physical DIRECT prototype

Date: 2026-11-03. Release status: **NOT READY, NOT SUBMITTED**. Owner requires fully automatic Safari failed-host recovery without manual additions or page reload, and no unrelated same-CDN-IP traffic leaving the proxy.

## Hardware-proven stage: fresh subsequent TCP/TLS connection

On physical iPhone 13 iOS 27.2 using explicit opt-in Debug QA, tun2proxy v0.8.3 with pinned experimental scoped-direct patch and a temporary mock HTTP CONNECT proxy on the local LAN:
- The mock proxy answered healthy CONNECT for www.cloudflare.com; two www.apple.com CONNECT sessions timed out.
- The Tunnel observed separate failing sessions, independently established two physical-interface TLS probes to www.apple.com, and dynamically approved that **exact virtual-DNS hostname** (not its destination real IP).
- A **fresh fourth client TCP/TLS flow** for www.apple.com opened an iOS IP_BOUND_IF bound TCP socket, completed TLS, and received actual response bytes. The mock proxy recorded two, not three target CONNECT requests.
- Event log (UTC, November 3): 11:43:17 probe started, 11:43:19 probe results 1+1 and dynamic approval, 11:43:24 physical bound TCP accepted / TLS ready / received data.
- Physical XCTest PASS with actual TCP + TLS evidence, not merely a timer: /private/tmp/apl-smart3-direct-evidence-guard-real2-20261103.xcresult.
- This earlier test proved only a fresh app flow; later full same-flow TLS and real Safari A-to-B recovery both PASS. Shared-IP isolation and Apple support are separate release gates.

## Same captured TCP stream — PHYSICAL TLS PAYLOAD ACCEPTANCE PASSED

- Rust pinned patches under mobile/ios/Tools:
  1. tun2proxy-split-dns.patch
  2. tun2proxy-flow-intent.patch
  3. tun2proxy-experimental-scoped-direct.patch (never enabled by default)
  4. tun2proxy-sameflow-scoped-retry.patch (strict DEBUG laboratory mode only).
- Same-flow patch retains the original captured virtual-DNS-addressed TCP stream after a real proxy handshake timeout/refusal, waits at most five additional seconds for the **already approved** exact-host physical direct proof, then substitutes an interface-bound direct TCP socket into the original stream without requiring the app to initiate a fresh connection. Failure remains fail-closed. Distinct lab event 7 means same captured flow recovered, not merely a fresh new flow event 6.
- Strict physical QA now requires BOTH an original stalled TLS session receiving actual payload and a subsequent fresh DIRECT TCP/TLS session receiving payload; no synthetic PASS after sleeping.
- New bounded, no-forwarding LAN fixture: scripts/qa_smart3_scoped_direct_proxy.py, requires explicit --physical-lab, local private IPv4 and fixed 18081 port, auto-stop 115 seconds.
- Verified exact Rust source patch replay with git apply --check and byte-for-byte source comparison. Cargo 1.98.1: 12/12 Rust tests PASS; iOS ARM64 release Rust static library compiles; signed iOS Debug build-for-testing and unsigned iOS Release build PASS; 131 Swift Core tests PASS and 151 iOS Python contracts + 73 subtests PASS.
- **03 Nov 16:34 MSK real iPhone PASS**: /private/tmp/apl-smart3-direction-physical-20261103.xcresult, `testExperimentalScopedDirectAfterTwoFailures() Passed (41s)`. The mock received two blocked `www.apple.com` CONNECT sessions and upstream healthy CONNECT. Distinct physical event evidence: at 13:34:10 UTC independent probe started, 13:34:12 2/2 physical TLS probes passed and host armed; 13:34:12.372 and .379 two **original** captured TCP streams recovered, each transferred first client bytes and server bytes, then each completed TLS and received HTTP response bytes without reconnect; 13:34:25 a **fresh fourth** TLS flow also completed physical TCP, both directions, TLS handshake and response bytes. XCUITest has explicit assertions for both old and fresh application payload. No forced page reload. Per-host flow attributed by VirtualDNS fake-IP mapping; no global IP-wide excludedRoutes added.
- Previously at 16:23 and 16:28 MSK two strict tests **FAILED** because original/fresh TLS payload was absent: event7/physical TCP alone did not count as success. Corrected the **DEBUG-only** proxy handshake deadline from 12 seconds to 4 seconds. Release/non-lab deadline remains 12 seconds. Added event 8/9 to measure actual first client/server TCP chunk without storing packet contents. Successful test followed these changes.
- Full iPhone user's saved state was restored after the test: 11 App Group and 20 app preferences match the pretest SHA-256 digest for every key, including proxy profiles. Diagnostic snapshots are private under /Users/master/Library/Application Support/Arvectum/ios-020-smart3-sameflow-20261103/. The temporary LAN proxy auto-stops after 115 seconds.
- This original test uses app NWConnection; real Safari is separately accepted above. NetworkExtension TN3120 remains a release blocker; experiment is disabled for Release.

## Real Safari A to auth-like B — PHYSICAL PASS at 16:54 MSK

Actual Safari on iPhone13 opened http://start.qa-example.test/ and received
HTTP 302 to https://www.apple.com/. The bounded LAN mock observed two origin
CONNECTs, one successful redirect and two blocked target CONNECTs. No target
traffic was forwarded through this mock.

Real tunnel events in UTC: 13:54:22 origin proxy CONNECT healthy, 13:54:30 and
13:54:39 target CONNECT failures, 13:54:39 physical DIRECT verification
started, 13:54:41 two independent TLS probes PASS and exact hostname armed,
13:54:41.535 original Safari TCP flow recovered without manual reload,
13:54:41.541 outgoing TLS bytes and 13:54:41.603 incoming server bytes.
Safari accessibility showed the shortened apple.com address and Apple iPhone
homepage contents. Physical XCTest PASS (37 sec), result:
  /private/tmp/apl-smart3-safari-final-physical-20261103.xcresult

A previous negative test required literal www.apple.com in Safari chrome,
which iOS shortens to apple.com. The stricter revised check validates the
displayed domain, actual iPhone page contents, original TCP flow recovery
and independently observed direct client and server bytes. No test client
pre-armed the route: Safari alone generated the redirect and two proxy
failures. Private app data: all 11 App Group and 20 app preference values
restored and verified byte-for-byte-equivalent by per-value SHA256.

This proves Safari A to B automatic recovery on the physical device in
bounded DEBUG QA; it does NOT establish Apple-supported consumer distribution,
same physical CDN IP peer isolation, QUIC/DoH/ECH safety or recovery after
network changes. No App Store build has been submitted.

## Safety, privacy and distribution gates

- The flow classifier requires a host from VirtualDNS's 198.18/15 fake destination mapping; never authorize raw IP, unbound socket, IPv6 unknown host, HTTP Host, bare SNI, guessed CDN sharing or wildcard domain. Already set public API capability flags remain false for Release. None of these tests authorize automatic IP-wide excludedRoutes.
- 31 preferences (11 App Group and 20 app keys) restored after the fresh-direct physical test, with per-key SHA256 exact matching. After the successful same-flow test the fresh baseline App Group and app defaults were restored with 31/31 SHA-256 per-key matches.
- Apple TN3120 explicitly advises against selective alternate-interface forwarding by NEPacketTunnelProvider. Technical proof on hardware is **not** Apple's supported consumer iOS distribution permission. Need documented Apple-supported deployment or Apple DTS confirmation before enabling the scoped physical transport in Release.
- Production routing remains unchanged; iOS 0.2.0 Draft PRs #296/#302/#303/#304 stay unpublished. Do not merge/upload an interim partial implementation.

## Required next acceptance tests

1. DONE: strict app same-flow TLS and real Safari HTTP redirect to HTTPS target, independent learned DIRECT and actual page render PASS.
2. DONE for baseline Safari navigation and original-flow recovery; still test learned persistence, 24h expiry, network changes and rollback.
3. On one real shared-CDN IPv4 **and IPv6**, prove only the exact host bypasses; unrelated second host stays on upstream proxy; block ECH/QUIC/DoH/raw-IP/unknown host direct leaks.
4. Obtain Apple supported consumer Packet Tunnel per-host physical-egress confirmation or supported alternative without IP-wide leaks; only then consider preparing final signed app, App Store Connect build number and submission.

No part of this document authorizes publication of iOS 0.2.0 or weakening its original required functionality.

## 19:58 MSK — Same-CDN IPv4 hostname isolation, real iPhone PASS

Mac mini DNS reported 23.12.156.37 for both www.apple.com and www.apple.com.cn. With explicit bounded, no-forwarding mock HTTP proxy on physical iPhone 13 iOS 27.2, two blocked target CONNECT sessions triggered two independent physical TLS probes and exact-host DIRECT. Both original TLS sessions recovered and received HTTP bytes, a later fresh TLS session also received response bytes. **The other hostname www.apple.com.cn remained on the proxy** (one independently observed NEIGHBOR_PROXY_CONNECT). Test XCTest PASS, 40.645 seconds: /private/tmp/apl-smart3-final-shared-cdn-green-device-20261103.xcresult.

Separate script scripts/qa_smart3_physical_evidence.py verified the App Group events and upstream mock log: proxy target failures 2, neighbor proxy CONNECT 1, sameflow recovered 2, original TLS data 2, fresh TLS data 1. The initial runner failed to initialize automation; a subsequent run falsely missed two older, offscreen entries in the virtualized UI list. The underlying telemetry contained both. Corrected GUI checks plus separate full-event audit PASS. All 11 App Group and 20 app preference values were restored to pre-test SHA256-identical values; private snapshots on Mac mini under /Users/master/Library/Application Support/Arvectum/ios-020-smart3-final-20261103.

**Boundary:** same public CDN IP was established from Mac DNS, not dual iPhone packet captures; the mock deliberately did not forward the proxy-only hostname. Therefore physical exact-host **route selection** is proved, but identical actual remote IP on both phone connections is not independently captured. IPv6, QUIC/ECH/DoH, handoff and Release enabling remain open. Not an Apple Review approval or release.
