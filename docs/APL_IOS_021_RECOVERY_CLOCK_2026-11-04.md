# iOS 0.2.1 — bounded recovery under system clock rollback (4 Nov 2026)

## Actual problem

The iOS ConnectionPressurePolicy and TunnelAutoReconnectPolicy used wall-clock Date for their recovery windows. If the iPhone clock moves backwards substantially (for example after a manual change or time synchronization), the negative elapsed time would keep the original recovery timestamp in the future. Even persistent socket overload could then be prevented from triggering automatic engine recovery until the clock caught up.

## Minimal correction

- For short backward corrections (within the existing 2-minute recovery cooldown), retain the cooldown to avoid rapid recycling after small NTP adjustments.
- For large backward corrections, drop the obsolete last-recovery anchor and let the existing hard/soft pressure gates operate as normal. Set the new anchor to the corrected current time.
- For automatic tunnel reconnection, discard attempt timestamps outside the bounded 10-minute window in both temporal directions, while keeping the normal 3-attempt cap across small clock changes.
- No change to socket thresholds, switching suppression, profile selection, network routes, Keychain, VPN configuration, App Store 0.2.0(48), advertisements or user devices.

## Verification

- Two new deterministic Swift Core cases check small rollback, 1-hour rollback, retry-budget reset and unchanged manual-disconnect behavior.
- 137/137 full Swift Core tests PASS and 104 iOS Python tests PASS (1 skipped).
- ARM64 iOS Simulator app+PacketTunnel compilation checked separately.
- This change addresses a bounded recovery corner case; it is **not** a demonstrated root-cause repair for CLOSE_WAIT accumulation. Separate macOS socket ownership investigation remains in progress.

## Next acceptance gate

After the macOS socket lifetime root fix is proven, compare the shared engine behavior on iOS before any live-device rollout. Avoid restarting or altering owner VPN/proxies to simulate failure. Version 0.2.1 is not submitted to Apple; no production release claimed.
