# macOS 0.2.21 regression: unexpected disconnect on socket-pressure recovery

## Confirmed physical evidence (MacBook Air, 2026-11-03)

- Installed 0.2.21 build 12, NetworkExtension active in manual proxy mode.
- Latest 40 shared telemetry events: 9 occurrences of `switch failed` with `Previous network engine did not stop within 5 seconds` and 22 `connection pressure` events.
- Repeated cycle: socket pressure (up to 110 upstream sockets, 81 CLOSE_WAIT) -> tun2proxy stop request -> engine drain timeout -> `cancelTunnelWithError` -> VPN disconnected; connection restored only after manual Connect.
- This is a confirmed local lifecycle regression; no evidence that the upstream proxy itself spontaneously disconnected.

## Fix

1. Apple `tun2proxy` v0.8.3 patch: retain previously required non-exiting API and split DNS patches, but wrap the asynchronous engine in a one-second forced cancellation fallback after stop token; then use Tokio `shutdown_timeout(2s)` instead of unbounded runtime destruction. This bounds the native engine's shutdown for long-lived TCP sessions while preserving the engine serial handoff.
2. macOS UI: after an extension-reported `switch failed` event no older than 45 seconds, attempt one delayed recovery when the app had actually observed an active VPN. Limit to three automatic recovery attempts per ten-minute window; prevent repetitive handling of the same event.
3. Explicit Disconnect in APL cancels the recovery; a `.userInitiated` stop from macOS System Settings is also logged and suppresses auto recovery.
4. Neither another VPN nor system proxy settings are changed; existing iOS app does not adopt the macOS reconnection behaviour.

## Validation gates

- Native Catalyst tun2proxy static library rebuilt with Rust 1.98.1; patched library SHA-256 `5a34d8d1a013b0f7b0886b42b5dcad55670fbe0fe19f764fb29abd9212777387`.
- 7 Swift `ConnectionPressurePolicyTests` passed (including explicit disconnect, stale failures and bounded retries).
- Isolated macOS Catalyst unsigned build and Apple Distribution archive 0.2.21 (14) succeeded, archive `codesign --deep --strict` passed.
- Real MacBook physical test and internal TestFlight validation must be completed before any public release.

## Physical test checklist

1. Back up installed build 12 under `~/Library/Application Support/ArvectumQA/20261103/original` (done, codesign verified).
2. Install signed internal TestFlight build 14 (not App Store public release).
3. Check profile selection, DNS virtual address, HTTPS access and sustained load including recovery threshold.
4. Confirm no more `switch failed` 5-second timeouts, no VPN disconnect or unintended auto reconnect on explicit Stop.
5. If fail, restore original build 12, maintain user data and do not publish.
