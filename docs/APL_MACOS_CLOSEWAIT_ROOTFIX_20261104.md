# APL macOS: устранение накопления CLOSE_WAIT, 04.11.2026

Status: code and unsigned full Mac Catalyst Debug build PASS; beta/public release NOT yet performed.

Incident: public MacBook APL 0.2.21(15) telemetry recorded up to 1689 upstream TCP / 1655 CLOSE_WAIT connections; later 66/24. Backup proxy 200.0.60.91:9448 works; upstream PX6 primary 68.209.60.141:8000 separately times out. Existing signed App Store APL on MacBook is still installed and working.

Cause: upstream tun2proxy v0.8.3 waits via Tokio join for both TCP copy directions. If upstream proxy sends FIN while the virtual client keeps its sending half open, the real TCP socket can remain indefinitely in CLOSE_WAIT.

Fix:
- Add bounded_half_close to pinned native source: after upstream FIN wait 2 seconds for client; after client FIN allow 30 seconds for response, then drop other future and release both sockets.
- Preserve full Smart3 flow callbacks/scoped direct native FFI in Mac Catalyst's pinned Rust build.
- Mac Catalyst only: cap tun2proxy to 96 simultaneous sessions vs advertised account-wide provider limit 200, tune pressure monitoring to avoid restarts on ordinary bursts.
- Fix missing current Swift UI source wiring in Mac XcodeGen, no UI behavior change.

Verified:
- Four Tokio/Rust tests passed, including a REAL loopback TCP FIN where browser side stays open.
- Pinned native ARM64 Mac Catalyst library and required Smart3 FFI built.
- Mac App Store contracts 23/23, appearance 5/5, new socket contracts 3/3 passed.
- Full unsigned app and PacketTunnel Mac Catalyst Debug build PASS on Xcode 27.1.
- Public MacBook 0.2.21 has NOT been replaced, profile data and ARC/Tailscale remain intact.

Not yet proved: long physical QA of new signed beta, App Store distribution, account-wide 200-session safety if all five devices are fully saturated. Do not claim public fix before TestFlight/real QA.
