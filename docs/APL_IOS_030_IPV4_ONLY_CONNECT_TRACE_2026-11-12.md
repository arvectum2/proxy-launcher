# APL iOS 0.3.0 — physical IPv4-only CONNECT event trace

Date: 2026-11-12 ~23:27–23:29 MSK. Owner's iPhone13 iOS27.2.1, signed Development Debug APL 0.3.0(49), original three user profiles and Keychain credentials.

## Purpose and safeguards

A previous physical PacketTunnel test timed out to the IPv4-only HTTPS hostname ipv4.icanhazip.com (-1001) even though the Apple ephemeral authenticated per-session proxy succeeded through all three saved profiles and public numeric Cloudflare IPv4 HTTPS through PacketTunnel changed the public egress address. Physical getaddrinfo showed a valid tun2proxy VirtualDNS 198.18/15 synthetic A record, so a general DNS resolution failure was not supported by evidence.

The existing Rust tun2proxy native per-flow callback already emits codes 0=CONNECT_OK, 1=timeout, 2=refused, 3=other and 4=upstream down. This QA stage does NOT patch Rust or routing. A source-only Debug gate qaTracePublicIPv4Only is accepted by PacketTunnel only when its stopAfter value is exactly 25 seconds. A separate signed app-hosted XCTest supplies this flag and arms a second 20-second host stop. SmartFlowEventCollector records at most eight events for the exact PUBLIC test hostname, writing only numeric native_code, not the hostname, IP, proxy endpoint, credentials, UUID, URL or response body. The app normally does not activate this gate. On simulator the hardware QA skips, and no QA condition is enabled in Release.

## Three independent signed real-iPhone tests

| Attempt | HTTPS inside real PacketTunnel | Native Rust code | Posttest |
|---|---|---|---|
| 1 | HTTP200 PASS | 0, CONNECT accepted | OFF independently confirmed |
| 2 | HTTP200 PASS | New code 0, no failures | OFF independently confirmed |
| 3 | HTTP200 PASS | New code 0, no failures | OFF independently confirmed |

After attempt 3 the protected App Group preferences were copied via CoreDevice. User profiles.v1 exact bytes and selected_profile_id match the original post-upgrade snapshot; all three original profiles exist. Cumulative anonymous QA event types: native_code=0 three times; native codes 1,2,3,4 zero. This code is a CONNECT handshake signal; the independently observed HTTPS HTTP200 confirms application data receipt. The test does not measure QUIC, IPv6, DNS leaks or handoffs.

## Interpretation

The previous -1001 timeouts are NOT deterministic: three consecutive real VPN connections to the same IPv4-only hostname now succeed with unchanged routes and profiles. No production fix was applied. Candidate dependencies include network path/transience, cache and proxy state and iOS timing; none is proven. Do not label this as permanently corrected until controlled repeated tests under differing network conditions.

## Validation

- [x] Signed physical iPhone QA, 3/3 successful CONNECT+HTTP200, two independent 20s/25s auto-stop guards, actual shorter completion and OFF.
- [x] Independent signed Network Extension OFF after all cycles, and App Group profile data bytes/selected UUID intact.
- [x] Full local source suite: Python333/333 +1513 subtests, Swift226/226 PASS.
- [x] Simulator physical-only QA: one XCTSkip, zero failures, TEST SUCCEEDED.
- [ ] Signed production-release PacketTunnel live IPv6, DNS leaks, UDP/QUIC, path switching/fail-closed and native VLESS/WG/AWG remain unaccepted; CloudKit and encrypted backup not shipped.
- [ ] Two-stack acceptance stage remains blocked pending stable IPv6 from an upstream that supports it, and repeatability testing of earlier IPv4-only transient timeouts.

All raw diagnostic logs and protected owner settings snapshots remain only on Mac mini. This research does not authorize App Store publication.
