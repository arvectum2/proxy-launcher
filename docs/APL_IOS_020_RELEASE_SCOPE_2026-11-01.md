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

## Diagnostic privacy and short-list retry hardening — 2026-11-01

- New Packet Tunnel event details use stable `ProxyFailureReason` codes instead of arbitrary third-party NSError descriptions; a successful-connect event records transport/latency, not upstream hostname or URL. Auto failure lists use positional indices and stable codes rather than profile name and raw error strings.
- `connectionCandidates` excludes the currently suppressed recently failed endpoint rather than retrying it merely because a list contains fewer than six profiles. Manual direct connection and separately throttled primary-recovery checks are unaffected.
- Targeted privacy source contract and new Swift suppression regression cover just these changes; retain earlier green core/UI/CI results without full reruns.

[Полный контракт зашифрованной резервной копии](APL_IOS_020_ENCRYPTED_BACKUP_FORMAT.md).

## P1 encrypted profile backup — source implementation 2026-11-01

- User-initiated `.aplbackup` FileDocument export and system Files import, with a passphrase (at least 12 characters), confirmation before encryption, and explicit warning that the passphrase cannot be recovered. The only file written is an encrypted AES-256-GCM container; source profile hosts and Keychain credentials are not present in readable JSON.
- Derivation: CommonCrypto PBKDF2-HMAC-SHA256 (210,000 iterations, 128-bit unique salt), CryptoKit AES-GCM with randomized nonce and authenticated ciphertext. Format/method/iteration count and file size checked before KDF, authenticity verified before JSON decode. Password is never saved in UserDefaults.
- Backup includes up to 200 profiles with credentials plus favorites and groups. Restore validates content and cumulative quota first, skips duplicates and remaps imported UUIDs; no existing profile/password is overwritten, no automatic VPN reconnect. Partial import failure attempts rollback and reports incomplete cleanup explicitly.
- Focused Swift codec/restore-plan tests and simulator build completed; device-facing Files export/import interaction and physical Keychain round-trip remain release acceptance gates.

## Explicit checks of selected proxies — 2026-11-01

- In multi-select mode, users can run one on-demand latency/authentication probe for precisely the 1–10 currently selected visible profiles; selections over 10 are rejected before network activity with a clear hint.
- This check shares the existing global 10-second manual cooldown, no-overlap gate and failure classification, preserving the rotating ten-profile cursor for subsequent bulk checks. No new connections are created by selecting/organizing profiles alone.
- One new Swift policy test, one iOS source contract and one ARM64 simulator Debug build PASS; all prior successful test suites were deliberately not repeated.

## Physical banner and compact UI — 2026-11-01

- Physical iPhone 13 with 0.1.42 (47) lacked visible ads. Source investigation found a first-load `.onAdFailure` that hid the footer permanently. The updated 0.2.0 QA build manually initializes SDK, preserves the production adUnit `R-M-20288304-1`, allows at most one 45-second retry, and uses the available display width. Ads remain non-blocking; no ad-dependent Connect logic or widget.
- On real device, a production-network Yandex Business creative **rendered** and the local SDK callback reached `impression`. This was not a demo ad or simulated screenshot. The app was updated in place from 0.1.42 to development-signed 0.2.0: three saved profile JSON entries and IDs were byte-for-byte equivalent as objects after update; no uninstall. App Store Connect privacy declarations and product metadata were not modified.
- Main screen reduced to Connect, connection state and active proxy with Change. Profiles use concise Add/Import/Backup actions, selection options move into an Actions menu, and priority/failback configuration remains in Settings. In-app privacy copy now accurately discloses that the Yandex SDK is present.
- Controlled live VPN smoke gate completed after triaging an unrelated system low-battery 10% alert that obscured the screen. The physical 0.2.0 test performed actual profile-tab actions, Connected state, an external `https://example.com/` HTTP 200 through the active tunnel, and verified OFF after disconnect. Result: 1/1 PASS with the pre-existing 20/25s temporary-tunnel safeties; this gate does not prove public IP change or multi-proxy failover.
- Immediately after device XCTest, restored the ad-enabled development-signed 0.2.0 binary. Re-read app group preferences: three profiles and UUIDs still identical to 0.1.42, existing keys preserved; Yandex SDK again reported `impression`. These QA preferences remain privately backed up on Mac mini, not in the repository.
- App Store distribution and TestFlight still gated on real Files backup/restore acceptance and cross-provider egress/failover checks as appropriate, actual release signing and separate authorization; a locally development-signed device test is not a public release.

## Ergonomic iPhone Home — final layout review, 2026-11-01

- iPhone-only order explicitly specified by owner: wordmark/header, real Yandex production banner, primary Connect/Disconnect, single active-profile selector, native system tab menu anchored at the bottom.
- Advertising component moved from the global `TabView` sibling/footer to directly under the Home header, with one instance only. No additional ad is inserted on non-home tabs. iPad/compact sizes retain an unscrollable Home and dynamic width with a maximum 580-point action column.
- Removed the redundant Connection and Profile cards on iPhone only; the status is a small non-button label below Connect, and the active profile is one selector button with its name. Existing macOS Catalyst cards remain unchanged. The existing Arvectum bitmap wordmark is preserved; adjacent text uses an optical vertical offset and matching bold weight.
- Real iPhone UI screenshot and focused source/layout assertions are the acceptance evidence, not a repeated VPN stress suite. Product release/Apple privacy approval remains separate.

## Revised ergonomic Home placement — iPhone device acceptance, 2026-11-01

- The user-requested larger banner uses the SDK's responsive `BannerSize.inline(width:maxHeight:)`, bounded at 120/160/220 points by viewport size, instead of stretching sticky creative. A live, real Yandex Business ad rendered in the larger format and reported an `impression` callback.
- The Home order is wordmark → inline ad → flexible space → Connect (plus a small status) → one profile selector → native tab bar. `Spacer` precedes both action controls to anchor them immediately above the bottom bar. No scrolling or extra prompts.
- First tab is explicitly **Домой** (`house.fill`), not a redundant fifth button; other tabs unchanged. macOS Catalyst preserves original `Главная` title and separate desktop layout.
- Signed physical iPhone 13 0.2.0 (48) installed in place and visually inspected. Three baseline profiles and previous UserDefaults keys remained unchanged. App Store Connect metadata was not touched. Source/layout tests and one device build PASS; earlier VPN suites intentionally not rerun.

## Native advertising and compact iPhone Settings — 2026-11-01

- Main Connect/Disconnect control is outlined on the disconnected state, bright only on active connection; the redundant OFF label is omitted. Transition status is retained and screen-reader labels still describe the action.
- A second ad slot between the main inline banner and the primary Connect action prefers **real Yandex native unit `R-M-20288304-2`**. SDK `NativeAdLoader` binds a registered `NativeAdView` including title, media, body, domain, sponsored label, age/disclosure and feedback/CTA assets; clicks and impressions are handled by `NativeAdDelegate`. On SDK failure it falls back to a short regular banner. The second slot is disabled for height under 650 points; the native/Home layout never uses ScrollView.
- Physical iPhone 13 received in-place a development-signed 0.2.0 build with production Yandex ads. Separate status keys confirmed both primary banner and native ad `impression`. Screenshots were inspected; old profiles remain untouched. Yandex native SDK initially rejected a view missing the domain asset; fixed by binding the domain, favicon, age and other asset outlets. Native load and impression were then directly verified on the iPhone; App Store privacy declarations were not changed.
- `profile.port` is rendered as an ungrouped decimal string, never a localized numerical quantity; e.g. `8000`, not `8 000`.
- Settings: compact rows for theme and language; inline dropdown language menu, no redundant heading/subtitles. Automatic backup routing is renamed **Primary proxy / Return to primary** with a right-hand toggle; OFF stays on a working backup and avoids switch churn. All actions remain reachable. Single focused QA test on iPhone 13 Simulator PASS (12.642s), with saved Settings screenshot showing all rows, including toggle and version, on one screen without scrolling. `ViewThatFits` uses a scroll fallback on small devices and large Dynamic Type (iOS 15 remains supported). On physical iPhone, XCTest automation was blocked by iOS's passcode authorization; no passcode was entered and no real credentials or profiles modified.
- App automation instructions reduced to selectable behavior plus the two required Shortcuts triggers; no duplicated help paragraphs.

## Release acceptance

- Physical iPhone upgrade from 0.1.41 retains every saved profile, exclusions, credentials and existing Shortcuts workflows.
- Import TXT/CSV/XML, bulk management, health checks, fallback and Home connect/disconnect verified on device.
- Ads render in the main app under permitted conditions; no new bypass surface; confirm ad integration and disclosure requirements.
- Bounded health-check traffic, no credential exposure, no connection leaks or failover loops.
- Targeted Swift/unit/UI tests, TestFlight smoke and release build pass before App Review submission.
- App Store publication is a separate explicit release action.
