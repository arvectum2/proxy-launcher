# APL macOS — wake guard auto-reconciliation, 28.10.2026

## Why this update was necessary

Older [PR #160](https://github.com/arvectum2/proxy-launcher/pull/160) addressed a wake-guard expiry issue, but it targeted the retired v0.2.13 UI code and attempted to replace the live `.agent/current-task.yaml`. The current canonical `main` has since changed the macOS UI policy: **ordinary Off remains available** even during the wake safety window, while **network rollback / recovery is guarded**. Transplanting the older PR verbatim would regress this distinction.

The current source still armed the guard and immediately refreshed its UI, but did not guarantee a later refresh when the timer expired unless a focus/user action occurred. A recovery control could therefore stay disabled after the intended safety interval.

## Source-only solution

- Schedule a dedicated `root.after()` callback when a long heartbeat gap arms a macOS guard, and when a destructive recovery action is deferred.
- On wake expiry, check for a **new** event-loop gap before updating controls; if the device slept again, re-arm and reschedule without exposing a premature rollback action.
- On real expiry, emit `proxy_gui.wake_guard.expired`, reconcile any pending lifecycle state and then refresh the GUI.
- Preserve safe/available ordinary Off path, all existing network rollback policy, proxy worker processes, settings, launch agents, and user data.
- No timer runs on Windows/Linux UI when `_mac_ui` is false.

## Acceptance and explicit limits

- [x] `python3 -m unittest tests.test_proxy_gui`: **47/47 PASS** using `/opt/homebrew/opt/python@3.12/bin/python3.12` (Tk 9.1, no GUI window launched).
- [x] 12 focused wake-guard tests PASS: newly armed guard schedules expiry, expiry without focus refreshes, second sleep re-arms, ordinary Off stays actionable and rollback remains protected.
- [x] Static compile `proxy_gui.py` and `git diff --check` PASS.
- [ ] **NOT physical acceptance**: real MacBook sleep/wake, longer suspended GUI, Safari/ChatGPT egress, working proxy listener and actual manual Off/rollback; no machines or networking touched.
- [ ] No app package or public release; any future signed/notarized build has a separate owner-controlled gate.

This is a source-correctness fix and test-driven CI candidate only.
