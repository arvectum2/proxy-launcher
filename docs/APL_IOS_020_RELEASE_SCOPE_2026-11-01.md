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

## Implementation checkpoint — 2026-11-01

- Profile organization: separate versioned shared-defaults metadata for favorites and freeform groups (no changes to `profiles.v1` or Keychain format), filters/search, batch assignment and guarded multi-delete with per-item error reporting.
- Batch import triggers a single bounded diagnostics scan after persistence, rather than one asynchronous network check for every imported proxy.
- Metered connection protection: at most three prioritized sequential probes during automatic scans; manual explicit batches of up to ten, 180s/10s cooldowns and no concurrent scans; small handshake/CONNECT probes rather than speed-test downloads.
- Auto: existing primary and last-good priority preserved; remaining backups use recent (10-minute) locally stored latency samples, failed proxies still suppressed; no credentials in snapshots.
- Existing Home and Yandex banner code untouched; no new widgets or external quick-connect controls.
- Core module tests and iOS Simulator ARM64 build are gates for each increment. Physical iPhone advertising/VPN validation still pending; no release to Apple yet.

CI note: keep the historical 155-key catalogs unchanged; additional 0.2 UI translations live in separate `ProfileManagement.strings` resources and fall back to English. PR #296 remains Draft. Signed simulator import/search/favorite/delete UI test passed on 0.2.0 with synthetic credentials. Physical iPhone is currently unavailable.

## Source-only 0.2.0 (48) continuation

- Marketing/build version set to 0.2.0 (48), no Apple submission or metadata changes.
- A real ad-supported production build is not the same as the signed simulator UI pass; the latter verified credentials import, Keychain, favorites, and confirmed deletion of a synthetic test profile.
- Failover selection is bounded to six candidates per attempt to avoid dozens/hundreds of paid handshakes. The user primary and last-good are first; unavailable primary re-probes are throttled and consecutive failures/cooldown prevent flapping. Physical proxy/failover acceptance remains open.
- Tunnel startup tasks are cancelled on disconnect to reduce late starts after VPN stops. Password updates use atomic-in-place Keychain updates and commit profile metadata after the successful secret operation.
- Historical iOS localization catalogs keep their 155-entry contract. New copy lives in ProfileManagement.strings, with an English fallback.

Source QA summary (no iPhone): 83 Swift Core tests PASS, 53 iOS Python tests PASS, signed simulator UI smoke for synthetic credential import/search/favorite/deletion PASS; ARM64 iOS Simulator and generic iOS device Release builds PASS without distribution signing. Keychain *replacement* is source/build-verified but not separately accepted as a physical credentials-edit scenario. The production Yandex SDK is included in Release, but actual banner impressions still require the physical device.

## Follow-up source hardening — 2026-11-01

- Selection only acts on currently visible proxy rows; search and group-filter changes clear selection. The user can select all visible, deselect all, add/remove favorites in bulk or move selected proxies to a group without affecting hidden entries.
- Import on an existing installation preserves the currently selected profile and Auto mode. On a fresh install, only the first new profile becomes default. A partially failed import explicitly reports if the best-effort rollback was incomplete.
- Auto remembers last-successful only after the tunnel is actually applied. A mid-switch engine failure closes the tunnel with a real error instead of leaving a false green Connected state; candidate enumeration respects stop/cancellation.
- Verification strictly scoped to changes: one new ProfileOrganization unit test, five 0.2 contract tests and one ARM64 Simulator Debug build passed. Previously validated 83-test Swift suite / 53-test iOS contracts / signed UI smoke / iOS Release builds are **not** rerun as part of this stage.

## Release acceptance

- Physical iPhone upgrade from 0.1.41 retains every saved profile, exclusions, credentials and existing Shortcuts workflows.
- Import TXT/CSV/XML, bulk management, health checks, fallback and Home connect/disconnect verified on device.
- Ads render in the main app under permitted conditions; no new bypass surface; confirm ad integration and disclosure requirements.
- Bounded health-check traffic, no credential exposure, no connection leaks or failover loops.
- Targeted Swift/unit/UI tests, TestFlight smoke and release build pass before App Review submission.
- App Store publication is a separate explicit release action.
