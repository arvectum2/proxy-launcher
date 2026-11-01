# macOS Packet Tunnel DNS/socket recovery — 2026-11-01

## Incident observed on physical MacBook Air

- macOS APL 0.2.20 build 10, manually selected HTTPS upstream.
- At failure: 78 upstream TCP sockets, **56 CLOSE_WAIT**, virtual DNS
  requests to 1.1.1.1 and 8.8.8.8 timed out; the LAN router DNS worked.
- Stopping and restarting the VPN restored virtual DNS. A subsequent reload of
  the signed-in Safari ChatGPT tab restored the page.
- Curl initially received HTTP 403 with `cf-mitigated: challenge`. This is **not**
  sufficient evidence that OpenAI blocked the proxy IP. Safari opened after
  network recovery and reload.
- The old Safari error contained the MacBook's physical IPv6 address. This
  merits a separate IPv6-routing investigation if reproducible; do not claim
  the current change conclusively fixes a browser IPv6 bypass.

## Changes (candidate for the next macOS release, NOT build 10)

- Sample upstream socket pressure every 10 seconds (formerly 30).
- On **55+ CLOSE_WAIT**, request immediate recovery; on **25+ CLOSE_WAIT**
  in two consecutive samples, recover after a debounce. Existing 90/150
  upstream total-socket thresholds remain.
- Cooldown between recoveries: 2 minutes (formerly 15 minutes). This is
  intentionally bounded: transient bursts below the hard threshold do not
  cause reconnect loops.
- TLS-relay idle timeout: 75 seconds (formerly 90); sweep every 10 seconds.
- Wait up to five seconds for the old blocking tun2proxy engine to **exit**
  before queuing the replacement. On failure, report the VPN error and
  disconnect rather than pretending a broken tunnel is connected.
- macOS VPNController waits for the actual disconnected state before
  connecting a new session, with a bounded failure and rollback path.
- Regenerated the macOS Xcode project to include recently introduced shared
  Swift files and a Mac Catalyst-only empty banner placeholder (no mobile
  advertising SDK added to macOS).

## Verification completed

- Six targeted ConnectionPressurePolicy tests: PASS (including the observed
  56 CLOSE_WAIT state and debounce/cooldown).
- RelayConnectionPolicy smoke: PASS (9 assertions).
- Live loopback TLS-relay integration: 105 local clients; 90 upstream sockets
  at cap, **0 after idle reaping**, using accelerated test-only timeout.
- TCP CLOSE_WAIT diagnostic smoke: PASS.
- macOS Catalyst Debug build with `CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**.
- Only existing Sendable/AppIntents warnings; no new compile errors.

## Release acceptance (not yet performed)

1. Code review and CI on the fix branch; do not modify the Apple 0.2.20
   build 10 review submission or replace the live MacBook build until ready.
2. Build a separately versioned, signed candidate for physical testing.
3. Stress using the affected HTTPS proxy: alternating page load, virtual DNS
   (including after remote half-close), HTTPS keepalive and reconnect. Verify
   that socket pressure is recovered while VPN remains usable, no repeated
   reconnect loop, and `CLOSE_WAIT` falls.
4. Check fresh Safari connections over both IPv4 and IPv6 (not only curl),
   including ChatGPT login, plus unrelated sites.
5. Only after physical acceptance, submit a new Apple release. Existing
   App Store confidentiality and advertising settings must be preserved.

The code reduces a measured recurrence mechanism but does not guarantee
access against a remote site's independent access controls or a bad proxy.
