# APL iOS 0.2 — release scope and advertising-first UX

Status: approved scope, implementation in progress. Baseline: iOS 0.1.41; 0.1.42 bulk import already merged. Do not claim 0.2 shipped.

## Product guardrails

- The app Home screen with its Connect/Disconnect button remains the primary user journey. Keep the existing Yandex Mobile Ads integration and ad-enabled public flavor; validate real-device display and applicable Apple/ad-network policies before release.
- **Do not introduce a Connect/Disconnect home-screen widget, Control Center toggle, or newly promoted one-tap external entry point in 0.2.** Such entry points reduce app visits and monetizable ad inventory. Preserve existing iOS Shortcuts automation compatibility, but do not promote it as the primary journey.
- Never gate essential connection functionality on viewing/clicking ads or insert deceptive forced interactions. Never modify existing App Store privacy declarations as a side effect of feature work; separately review disclosures if implementation changes data practices.

## P0 delivery backlog

1. Profiles: bulk selection/deletion, folders/groups, favorites and search; migrate existing profiles losslessly.
2. Health checks: bounded, opt-in/test-on-demand reachability and latency; prevent excess connections and metered proxy bandwidth consumption.
3. Selection: deterministic best-healthy-proxy ranking, fallback/failback with cooldown and anti-flapping; keep manual selection available.
4. Reliability: timeouts, connection resource cleanup, meaningful status and failure diagnostics; protect credentials in all logs.
5. UX: improve Home and first-run guide, language clarity, accessibility and light/dark appearance without burying ads or the primary Connect button.

## Conditional P1 (must not delay stable release)

- Smart related-domain exclusions: feasibility and actual iOS packet-routing verification before user-facing promises.
- Explicit encrypted profile backup/export with credential warning and no plaintext diagnostic leaks.
- Per-profile DNS/IP/latency diagnostics, only where technically supportable on iOS.

## Deferred

- Home-screen widget and new one-tap external connect surfaces (monetization impact).
- VLESS+REALITY engine, proxy marketplace, multi-device sync.

## Release acceptance

- Physical iPhone upgrade from 0.1.41 retains every saved profile, exclusions, credentials and existing Shortcuts workflows.
- Import TXT/CSV/XML, bulk management, health checks, fallback and Home connect/disconnect verified on device.
- Ads render in the main app under permitted conditions; no new bypass surface; confirm ad integration and disclosure requirements.
- Bounded health-check traffic, no credential exposure, no connection leaks or failover loops.
- Targeted Swift/unit/UI tests, TestFlight smoke and release build pass before App Review submission.
- App Store publication is a separate explicit release action.
