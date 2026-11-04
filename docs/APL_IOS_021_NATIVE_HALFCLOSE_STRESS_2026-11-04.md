# iOS 0.2.1 — native TCP FIN/CLOSE_WAIT loopback stress QA

Scope: additional source-pinned Rust tests ONLY for draft PR #314. No
production runtime logic, PacketTunnel settings, Apple submission or user
iPhone/VPN/Keychain state changed.

## Specific risk

The experimental native tun2proxy half-close fix introduces bounded shutdown:
2 seconds after upstream server FIN, 30 seconds after client FIN. Previous QA
only covered one upstream FIN and pending futures; upload/download correctness
and repeated socket lifecycles required stronger proof.

Two additional cfg(test) Rust tests extend the source-pinned patch:

- Delayed response after client EOF: a real TCP loopback upstream receives
  and verifies a 32 KiB client upload, waits briefly, sends a 128 KiB reply,
  then sends FIN. The relay drains and validates both payloads byte-for-byte.
- Repeated upstream FIN: on 20 consecutive real TCP loopback sessions,
  the server sends a 4 KiB patterned reply then FIN while the simulated
  browser keeps its write half open. Every cycle must receive all 4 KiB,
  complete promptly and have its upstream peer observe real EOF instead
  of retaining the socket indefinitely in CLOSE_WAIT.

All socket servers bind only 127.0.0.1 using ephemeral ports; they make
zero connections to user proxies, Apple devices or external services.
The new tests live inside the existing Rust cfg(test) module and do not
alter compiled release behavior or its 2s/30s timeout trade-off.

## Verified evidence — 4 November 2026

- Pinned upstream tun2proxy v0.8.3 source SHA:
  e271de19683937f23d3f8f0eb4df0a61fc4a6e50.
- Six patches independently passed git apply --check and applied in order,
  including Smart3 dual-stack and the extended FIN/CLOSE_WAIT patch.
- Rust 1.98.1: all **23/23 native lib tests PASS**, including both new
  live socket upload/reply and 20-session repeated upstream FIN cases.
- Stress repetition: 25 consecutive complete runs of the 6 half-close
  Rust tests, **150/150 PASS**, including 500 separate real loopback FIN
  sessions in the repeated-connection test.
- Python source isolation contract: additional three checks, confirming
  the two scenarios and that the production upstream patch remains pinned.

- Native production libraries built successfully with pinned Rust 1.98.1 for
  aarch64-apple-ios and aarch64-apple-ios-sim. SHA-256 device:
  bc5baea1225974099da1825d748b2aa8e14bd58710873aca6e27869e6e39a7cb;
  simulator: ecb11db7415e3f3ec7a56e5fa328f0405c04ff685a51753605e977a7314f932b.
- Full source-branch Swift Core 135/135 PASS and iOS Python source suite
  111 tests (one skipped) PASS, including 7 targeted native source contracts.
- Byte-for-byte proof: removing only the new cfg(test) lines and reverting the
  patch hunk line count reproduces exactly the unmodified PR #314 patch.
  The production Rust relay logic and all 2s/30s limits remain unchanged.
- Reapplied the FINAL adjusted patch to a clean pinned clone after tests were
  added; all 23 native Rust tests PASS again (verified patch hunk integrity).

## Release blocker — not waived

These tests prove real socket-level lifecycle and payload correctness in a
local controlled Rust QA environment. They DO NOT prove real iPhone Packet
Tunnel egress, Safari upload/download, LTE/Wi-Fi transitions, proxy failover
or unexpected in-flight uploads after server FIN. In particular, the 2-second
server-FIN teardown can still interrupt an unusual legitimate browser upload.

Draft PR #314 must stay **DRAFT**, not be merged into main or submitted to
Apple until independent disposable-device FIN/CLOSE_WAIT and full traffic
acceptance is complete. Owner's decision to postpone the second-iPhone QR
test until after QR publication is unrelated to this native VPN safety gate.
