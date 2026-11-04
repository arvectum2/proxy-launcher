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


## FAILED 65-minute build16 MacBook physical QA (2026-11-04)

Observed 66 samples over 3900 seconds: TCP 58 to 282, maximum 308;
CLOSE_WAIT 18 to 141, maximum 172. HTTPS, VPN and ARC remained online,
but persistent FD accumulation is a RELEASE BLOCKER. More recent samples
reached 413 TCP / 265 CLOSE_WAIT, with recurrent internal engine handoffs
approximately every 125 seconds.

Original passive collector incorrectly marked PASS based only on connectivity.
Raw logs and its original verdict remain unchanged; independent socket-limit
acceptance evaluator returns FAIL on four separate resource criteria.
Eight automated regression tests passed.

New kernel-level Darwin TCP_CONNECTION_INFO watcher observes upstream FIN
even when virtual-client writes block and normal Tokio forwarding does not
complete. Requires two consecutive kernel CLOSE_WAIT observations before
dropping the owned upstream stream; does not close foreign raw FDs. New
macOS live TCP test with blocked virtual output PASSED; all five native
half-close tests passed. Build16 is REJECTED; new build17 required.


## Additional runtime-scoped cleanup in build17

Repeated in-process pressure recovery events were seen approximately every
125 seconds while sockets persisted across previous runner handoffs.
The pinned Rust engine spawned TCP and UDP session tasks detached from
its main accept loop. The revised native macOS patch now maintains a
tokio JoinSet, reaps completed session task results and explicitly aborts
and awaits every remaining task when the engine stops. The Session Handoff
barrier now follows native session teardown instead of only the accept-loop
exit. A new real-loopback session test confirms the held TCP socket
releases after abort/drain. All SIX native tests pass on Mac mini.

Build17 needs a signed rebuild with this *final* patch; an earlier locally
signed build17 archive with only the kernel watcher is superseded, and has
NOT been uploaded to Apple.


## Build17 signed TestFlight installation and physical retest (2026-11-04 ~16:35 MSK)

Previous beta16 65-minute test is REJECTED, independently re-evaluated as
FAIL due to 308 TCP/172 CLOSE_WAIT peak and final 282/141. Signed beta17
contains the native Darwin TCP_CONNECTION_INFO CLOSE_WAIT watcher and
explicit join/abort drain across engine handoffs. Server validation and
upload of beta17 succeeded; App Store Connect says VALID and Internal QA
IN_BETA_TESTING.

MacBook GUI TestFlight showed 0.2.22 build17 and updated it in place;
application version 17 confirmed; three existing profiles retained,
selected Netherlands 2; VPN Connected, egress 68.209.63.122,
HTTPS 200. ARC/Tailscale userspace backend Running and independent external
Funnel responds HTTP 401 (correct authorization boundary). After installation
first socket sample had 17 TCP / 0 CLOSE_WAIT; a 20-request concurrent HTTPS
probe returned HTTP 200 for all requests and 49 TCP / 17 CLOSE_WAIT afterward.

Read-only physical QA restarted as *v2* because userspace Tailscale's cached
Self.Online reported false even while the external ARC HTTPS Funnel was
reachably responding HTTP 401. The revised monitor samples actual local ARC
HTTP readiness plus Tailscale Running and independent external checks from
Mac mini. The initial raw v1 log is retained separately, not overwritten.
Files on MacBook:
~/Library/Application Support/Arvectum/ProxyLauncher/qa/soak_0_2_22_b17_v2.start
~/Library/Application Support/Arvectum/ProxyLauncher/qa/soak_0_2_22_b17_v2.jsonl

An independent hardened evaluator in
mobile/macos-appstore/Tools/evaluate_socket_soak.py must analyze the full
3900 seconds before public review. No claimed success yet.

CI security jobs had failures setting up pinned Python 3.12.10 on
ubuntu-latest/26.04 (unrelated to app source). The affected three workflows
are now pinned to ubuntu-24.04, preserving the pinned Python version.

## First full build17 physical QA result: socket PASS, HTTPS FAIL (2026-11-04)

Strict independent evaluation of 66 samples over 3900 seconds in MacBook
qa/soak_0_2_22_b17_v2.jsonl returned FAIL. Kernel socket lifecycle
improved to max 48 TCP / 31 CLOSE_WAIT, final 14 TCP / 1 CLOSE_WAIT;
VPN, ARC and tunnel PID stayed stable. But two genuine HTTPS curl
timeouts (return code 28, HTTP 000) occurred at 903 and 1209 seconds,
about 16:52 and 16:57 Moscow. Twelve other scheduled probes passed;
HTTPS recovered without manual reconnection. Root cause of transient
outage (external proxy versus APL route) is NOT established.

Second full read-only 65-minute MacBook test v3 was started about
18:25 Moscow, with additional apple.com and github.com probes if
the primary example.com check fails; raw v2 evidence is retained.
Do not merge PR #310 or publish macOS 0.2.22 before full acceptance.

## Integration with QR sharing from latest main (2026-11-04)

Shared iOS ProfilesScreenView and AppViewModel also compile in the macOS
Catalyst app. After main merged iOS QR profile sharing, the macOS app
failed compilation due a missing ProxySharePresentation dependency. Added
only ProxyShareView.swift to the Mac XcodeGen app sources, regenerated
the Xcode project and added a regression contract. The merged Mac app
and PacketTunnel now BUILD, with 24 macOS contracts PASS. No changes
were made to iOS app source or the installed signed MacBook beta17.

Release-source caveat: signed Apple beta17 predates merged QR AppViewModel.
The integrated branch could produce a different Mac app binary. Exact
signed release source must be attested, and any changed integrated app
must be re-signed and physically regression-tested before publication.

Mac mini external ARC Funnel monitor showed one 18:30 timeout then three
HTTP401 responses at 18:32, showing the local ARC status alone does not
establish independent external availability. Monitor output is at
/tmp/apl_b17_external_arc_20261104.jsonl.
