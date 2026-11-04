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


## Apple TestFlight state and remaining physical gate (12:17 MSK)

The public MacBook 0.2.21(15) was measured with **274 upstream TCP / 170
CLOSE_WAIT**, all directed at the US backup 200.0.60.91:9448, after about
two hours of VPN uptime. The ordinary HTTPS proxy route still works, but
this is a real resource leak and may exhaust provider's concurrency limits.

PR #310 native Rust half-close fix CI passed 24 checks; signed 0.2.22
build16 archive signed and locally verified. The package was successfully
cloud-exported by Xcode. Apple server validation of a second copy returned
409 DUPLICATE: build 16 was previously uploaded. ASC API independently
confirmed existing version 0.2.22 build16 ID
7e9ea489-aa9c-4f51-8437-e0c1300a6dd3 is VALID (2026-11-04).
Export compliance reused prior macOS non-exempt encryption=false and the
build was added to existing internal TestFlight QA group, state
IN_BETA_TESTING. No need to upload another binary.

Before installing on MacBook, backed up existing public 0.2.21 app and
App Group preference plist to
~/ArvectumSafe/backups/APL-macOS-0.2.21-before-closewait-qa-20261104/.
Direct remote ARC MacBook GUI is offline; SSH and independent Tailscale
still work. AppleScript reports no accessible TestFlight controls, so
installation must be done by the owner at the visible TestFlight UI or
after restoring observable remote GUI. Never force an unseen GUI update.
No public 0.2.22 release has been submitted.

## Real MacBook TestFlight installation, 2026-11-04

ARC GUI recovered and a macOS Automation prompt to control TestFlight was
authorized after the owner explicitly requested installation. TestFlight
0.2.22 build16 was installed over 0.2.21 and App Store's request to close
the running APL was accepted. The old app and App Group preference plist
were backed up before installation.

Version 0.2.22 build16 and code signature verified. All 3 saved profiles
were retained and existing selected profile Netherlands 2 unchanged.
APL VPN Connected; external HTTPS egress 68.209.63.122; Tailscale/ARC
remains Running/Online. 30/30 controlled HTTPS requests returned 200,
initial TCP 48 / CLOSE_WAIT 21 and after load TCP 29 / CLOSE_WAIT 0.
The passive 65-minute MacBook QA monitor is running under user account,
logging to the local qa directory as soak_0_2_22_b16.jsonl and summary.
It never changes VPN state or profiles.

Short QA PASSED; full physical soak is still pending. Do not publish yet.
