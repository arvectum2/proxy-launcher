# iOS 0.3.0 — isolated UDP/QUIC-leak detection preparation

Date: 2026-11-13. Source-only/test-harness stage; **not a physical UDP leak acceptance**.

## Threat model and narrow claims

The production iOS PacketTunnel routes original IPv4/IPv6 packets through a pinned `tun2proxy` and HTTP CONNECT/SOCKS5 backend. The disposable laboratory proxy at `192.168.1.80:18081` only accepts explicitly allowlisted TCP CONNECT 443, never UDP. Any successful direct UDP datagram from a separately public IPv6 witness address **while this VPN is active** is a potential routing bypass, not a legitimate HTTP CONNECT route.

A lack of UDP echo on the iPhone is insufficient to prove absence of leakage: UDP could reach the server with its reply lost. The independently controlled UDP server must also show the *exact* number of accepted echoes: **three** (two direct preflight + one after VPN OFF), never four. Otherwise the test is inconclusive/failed even if the iPhone received nothing.

This single-IPv6-destination result does not cover DNS leaks, QUIC Initial/HTTP3, all interfaces, exclusions or network transitions. The current production app is not advertised as a universal UDP kill switch.

## Source gates

- Separate optional `mobile/ios/Tools/qa_udp_echo_witness.py`: explicit real public IPv6 bind only; 18991/UDP default; short lifetime (75s by default, max 120s), at most eight accepted 39-byte exact-prefix nonces (max 16 configurable). Exact 1:1 reply, no arbitrary forwarding/amplification, no endpoint or payload logging.
- Physical signed Debug XCTest `PhysicalDisposableIPv6UpstreamTests.testBoundedUDPDirectWitnessBlockedInPacketTunnelAndRestored`, compiled only with `APL_RUN_EXPLICIT_VPN_QA`. On simulator it **skips**. No implicit auto-run: `APL_QA_UDP_ENABLE=YES`, `APL_QA_UDP_WITNESS_IPV6=<globally routable literal>` and `APL_QA_UDP_WITNESS_PORT=18991` must be explicitly supplied in the XCTest runner environment.
- Before any VPN change: installed APL Network Extension must be OFF; UDP nonce echo twice; disposable no-failover HTTP CONNECT IPv6-only HTTPS preflight PASS. Missing prerequisites SKIP with system VPN untouched.
- Once started: only the hard-coded disposable HTTP upstream is permitted; 20s host stop plus independent 25s PacketTunnel stop, with `defer stopVPNTunnel` regardless of outcome. Must confirm real disposable HTTPS origin *during* VPN before classifying UDP result.
- While VPN ON: send one random 39-byte IPv6 UDP nonce; a matching response is an explicit failure, not an accepted proxy egress. Stop VPN and independently observe OFF; direct UDP echo must succeed again.
- Witness server process is not launched by the test and must be stopped. Owner's 3 saved profiles, Keychain, backup and App Store version are never mutated.

## Running the prepared test later (requires separate physical approval)

1. Confirm user data protected and APL VPN OFF. Verify a test iPhone with **matching signed Debug** PacketTunnel, plus connectivity to the separate IPv6 echo server and allowlisted disposable HTTP CONNECT upstream. The test endpoint **must not** be among manually approved DIRECT/bypass routes.
2. In a secured private terminal on the laboratory server, run `python3.14 mobile/ios/Tools/qa_udp_echo_witness.py --bind <server-public-ipv6> --port 18991 --lifetime 75 --max-echoes 8`. This is a temporary UDP listener and must never be kept running as a production service. Start the separate allowlisted IPv6 HTTP CONNECT test proxy on the Mac mini for the same bounded session.
3. Explicitly provide the three `APL_QA_UDP_*` test-runner environment values to the signed hardware XCTest scheme; do not configure them in app preferences, user profiles, production CI or source control. Launch only the named XCTest. Do not disable TLS trust, enable native DIRECT, or use the owner's original commercial proxies.
4. Review XCTest booleans (no raw addresses/names/secret logs), server `echoed=3`, independent VPN OFF proof, and byte-preservation of `profiles.v1` and selected UUID. Any different counter, unavailable baseline, VPN status discrepancy or missing test guard means **no acceptance**.
5. Review DNS provenance separately using controlled authoritative DNS and/or underlay packet observation. QUIC and Wi-Fi/LTE/handoff failure injection are separate physical gates.

## Offline verification

Python iOS source suite **347/347 PASS + 1527 subtests** (both standard-library unittest and pytest compatible; seven new unittest test cases pass), Swift core suite **226/226 PASS**. Unsigned ARM64 iOS Simulator Debug physical-QA XCTest build-for-testing **SUCCEEDED**, and unsigned iPhoneOS Debug physical-QA XCTest target **BUILD SUCCEEDED** with the explicit QA compilation flag. Both target builds compile the production app and PacketTunnel; the latter additionally type-checks the real-hardware-only XCTest body. **This is not a signed-device test.** Do not merge into `main` or submit iOS 0.3.0 until reviewed and hardware acceptance has passed.
