# Arvectum Proxy Launcher — remaining local / human / infrastructure backlog

Updated: 2026-09-26  
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Current stable release: `v0.2.16`

This file contains the remaining work that cannot be truthfully completed by hosted repository automation alone, plus active review/owner gates after the Windows/Astra/RED OS desktop baseline and registry dossier work.

## P0 — repository / executor baseline — DONE

- **DONE** — canonical repository is `arvectum2/proxy-launcher`; migration recovery and main-protection acceptance are historical closure.
- **DONE** — the single hourly `Proxy Launcher Watchdog` is enabled and reads `.agent/executor-policy.yaml`, `.agent/execution-queue.yaml`, `.agent/current-task.yaml`, this backlog and the canonical roadmap.
- **RULE** — watchdog may skip blocked HUMAN/OWNER gates to do later independent admitted preparation, but may not reorder the queue or invent scope/approval.

## P1 — current stable release `v0.2.12` — PUBLISHED

Published 2026-09-21 from exact release SHA `8d9a4e5913fa92b39f0f926004df6f1fd57f3bde`:

- Windows x64 Setup;
- Windows x64 portable ZIP;
- Astra Linux x86-64 DEB;
- RED OS 8.0.3 x86-64 RPM;
- generic Linux x86-64 AppImage;
- `SHA256SUMS.txt`.

GitHub release assets independently pass `sha256sum -c`; GitVerse metadata/assets/canonical-payload parity is recorded PASS.

Important boundary: current `main` is `df4478a70729e20f33b7a0d17476183423955576`, ahead of the immutable v0.2.12 release because PR #148 later merged free-proxy gateway/Android 0.1.31 work. Do not describe those post-release bytes as part of v0.2.12.

Historical progression:
- `v0.2.5` — Windows CFA-safe physically accepted baseline;
- `v0.2.6` — Windows + Astra release lane;
- `v0.2.7` — RED OS release track;
- `v0.2.8` — Linux mixed-state recovery hardening;
- `v0.2.9` — Windows saved-or-Arvectum recovery symmetry;
- `v0.2.10` — AppImage promotion;
- `v0.2.11` — Windows PAC/WPAD isolation + macOS Safari CONNECT hardening;
- `v0.2.12` — verified macOS long-sleep recovery + Android long-sleep/foreground reconciliation.

v0.2.15 remains the immutable ad-hoc macOS baseline. v0.2.16 is now published with Developer ID signing, Apple notarization/stapling, Gatekeeper verification and GitVerse payload parity; v0.2.15 was not modified.

## P2 — Astra Linux / Gate R8 — DONE / PHYSICAL PASS

- **DONE** — real Astra Linux Special Edition 1.8/Fly physical-host acceptance.
- **PASS** — install, GUI/runtime, NetworkManager enable/disable, no-proxy sync, exact rollback, autostart, crash recovery, reboot recovery, package lifecycle, diagnostics/privacy and cleanup.
- **DONE** — APL-LNX-011 Firefox system-proxy fix closed by PR #71/#72.
- **CURRENT RELEASE** — `v0.2.16` ships the Astra DEB; v0.2.9 remains the filing-evidence baseline.

Astra acceptance remains a trusted-OS compatibility evidence record; an exact-`v0.2.9` rerun is future-proof evidence, not a currently represented 2026 filing prerequisite.

## P3 — RED OS / APL-REG-001C — DONE / PHYSICAL PASS

- **DONE** — RED OS 8.0.3 Standard Desktop x86_64 physical acceptance, merged by PR #83.
- **PASS** — clean install and RPM verification, start/stop, byte-exact KDE + NetworkManager rollback, Chromium system-PAC routing, localhost no-proxy, emergency rollback, XDG autostart ownership, diagnostics/no-mutation, full remove/reinstall and final restoration.
- **PASS** — focused RED OS regression suite `62/62`.
- **CURRENT RELEASE** — `v0.2.16` ships the RED OS RPM; v0.2.9 remains the filing-evidence baseline.

Open preparation PRs #70/#74/#82 are superseded by the completed PR #83 path and are not active roadmap tracks.

## P4 — mobile + free-location track

### Android public baseline — `android-v0.1.19`

- **PUBLIC / MIRRORED** — Android 0.1.19 was published 2026-09-19 with the accepted site-exclusion UX/routing from APL-MOB-003.
- **HISTORY** — APL-MOB-001 transport/multiprofile, APL-MOB-002 Auto failover/network handoff and APL-MOB-003 exclusions are closed engineering tracks.

### Android sleep/wake recovery — MERGED

- PR #147 reconciles logically-ON VPN state when the app returns after long sleep and safely handles reclaimed/dead service or revoked VPN permission.
- The initial fix bumped the dogfood candidate to 0.1.20; it is included in the later 0.1.31 current-main baseline.

### Free RU/US proxy gateway — DONE / LIVE FRIEND-TEST INFRA

Merged PR: `#148`.

Completed facts:
- supplier proxy host/login/password stay server-side and are loaded only from secret environment/config;
- public API exposes only free location metadata;
- session API returns short-lived location-bound Arvectum gateway credentials, not supplier credentials;
- gateway is deployed as a launchd service on the Mac mini with secret env permissions and localhost-only origins;
- public TLS ingress is active;
- real RU upstream exits in RU and real US upstream exits in US;
- gateway tests and security scans pass.

Scale boundary:
- current gateway is appropriate for controlled/friend testing;
- it is **not** yet an anti-abuse system for large anonymous public rollout;
- per-install quotas/rate limiting/abuse controls require a separately admitted future task.

### Android free-location integration — DONE

- Android fetches free locations/session credentials from the gateway;
- only location selection is durable; short-lived gateway credentials are ephemeral;
- manual Primary/saved profiles remain supported;
- supplier secrets never enter the APK/runtime configuration;
- expiry/reconnect logic refreshes the gateway session rather than relying on stale credentials.

### Android 0.1.31 — MERGED FRIEND-TEST BASELINE / NOT PUBLIC RELEASE

Current source identity:
- versionName `0.1.31`;
- versionCode `32`;
- merged in PR #148 to current `main`.

Evidence:
- Android exact-head workflow: SUCCESS;
- lint: 0 errors / 8 intentional warnings;
- gateway tests: 13/13 PASS;
- gateway/security/SBOM/dependency/provenance checks: SUCCESS;
- RU→RU and US→US post-deploy checks: PASS;
- US soak: 15/15 PASS;
- exact-head APK SHA-256: `edf2026ec05405031924e2893efe2d422a7c3aeeeda89c22f3c50d871aa24b99`.

Boundary: no public `android-v0.1.31` release tag exists. Friend-test/merge evidence does not equal public publication.

### APL-MOB-004 — PLANNED / OWNER PRIORITY + PACKAGE-IDENTITY GATE

This remains a separate monetization/distribution track. The free gateway does not authorize ad integration.

- public ads-enabled channel: GitHub, GitVerse, Arvectum site and RuStore;
- initial target: Yandex Mobile Ads / App Open with first-launch grace, frequency limiting, fail-open behavior and privacy/consent documentation;
- private no-ads artifact from the same codebase, preferably via build flavor/configuration;
- private artifact must stay outside the public GitHub release surface;
- Owner must decide private package/update semantics and explicitly authorize provider/configuration work before implementation.

## P5 — IP / corporate rights boundary — DONE FOR CURRENT FILING EVIDENCE

Current final object: exact public `v0.2.9`.

Repository engineering and Owner-factual evidence are complete for the current filing packet:

- exact source/tag tree, promoted package digests, provenance and CycloneDX SBOM are governed;
- v0.2.5 -> v0.2.9 material drift is reconciled;
- the executed 2026-09-14 private sole-participant/rightsholder decision remains the operative chain-of-title evidence;
- the actual instrument was reviewed and identifies Arvectum Proxy Launcher without a version number, transfers the exclusive right in full and authorizes modification/reworking;
- current Rospatent, corporate/Russian-control and human creative-control facts were confirmed by the Owner;
- historical v0.2.9 filing scope: Windows Setup/portable, Astra DEB and RED OS RPM;
- Owner directive 2026-09-18 separately admits AppImage for the next release. This does not alter the exact v0.2.9 filing-evidence object or its already executed rights record.

The previously prepared R-1B two-party/future-rights agreement is **not required to complete this project filing-evidence task** and must not be presented to the Owner as a mandatory signature step. It is retained only as optional external legal hardening. A future registry/expert clarification or external-counsel review may still recommend a separate instrument for later human-authored copyrightable contributions.

Issue: `#57`. Current record: `docs/APL_IP_001_V0_2_9_SIGNOFF.md`.

### AppImage lane — DONE / PUBLISHED IN v0.2.10

PR #111 promoted the governed APL-LNX-008 AppImage lane into the canonical release set, and public v0.2.10 includes the x86_64 AppImage plus checksum coverage. The pinned type-2 runtime/source identity and runtime/third-party notices remain part of the packaging contract. DEB/RPM remain native preferred Linux packages.

## P6 — Russian Software Register sovereign lifecycle — BLOCKED / PHYSICAL INFRASTRUCTURE

APL-REG-001B repository tooling exists, but filing-grade physical proof remains open.

Required real chain:

`Russian authoritative source -> Russian-controlled source/object storage -> Russian build/compilation host -> governed/offline inputs -> exact artifacts -> Russian authoritative release/distribution storage -> evidence bundle`.

Do not claim GitVerse or another provider is compliant merely because it is Russian. GitHub remains useful for development/public distribution but does not substitute for the required physical lifecycle facts.

Issue: `#55`.

## P7 — Windows public trust / APL-REL-016 — READY FOR REVIEW REFRESH

Issue: `#30`. Latest substantive review PR: `#161`.

Historical preparation PRs #132 and #157 are superseded. PR #161 contains the latest substantive Windows public-trust packet, but it too is version-stale:
- its branch was prepared before immutable v0.2.16 became current;
- public v0.2.16 ships without native Windows Authenticode;
- therefore the first eligible future native Authenticode/public-trust release is now **v0.2.17+**.

Current action:
1. refresh/rebase #161 from current main against immutable `v0.2.16`;
2. set `v0.2.17+` as the first eligible future Windows native-signing release;
3. re-verify SmartScreen/App Reputation, Smart App Control/Application Control, managed-enterprise trust, CA/B Forum and provider geography requirements;
4. keep Russian detached CryptoPro/Rutoken evidence separate from Microsoft-native publisher trust;
5. stop at Owner review.

Provider/certificate spend, key custody, production signing, approval/merge of the decision packet and release remain Owner-reserved.

## P8 — per-application routing — CURRENT PREPARATION / OWNER DECISION

Current decision PR: `#144`. Stale predecessor PR #68 is superseded.

PR #144 carries the Owner decision packet and recommends, without approving, an Arvectum-owned WFP ALE callout + privileged service + local proxy path. Its current exact-head repository checks are green.

Current gate:
1. reconcile #144 wording/assumptions from immutable `v0.2.12` to **v0.2.16/current-main** recovery semantics;
2. preserve separate WFP ownership, foreign-resource non-ownership and the current APL-REL-016 signing dependency;
3. Owner/Product Owner selects or rejects the production architecture;
4. only after approval implement the privileged enforcement slice;
5. require real Windows host recovery/security acceptance;
6. release only as a new version.
7. Owner priority recorded 2026-09-26: application exclusions/routing are the next functional slice; after it reaches feature-complete acceptance, hand off to P8A before any public release.

No architecture is approved merely because the packet/tests are green.

## P8A — APL-UI-001 cross-platform Adaptive UI — IN PROGRESS / REVIEW GATE

Source design review: `docs/APL_UI_UX_CROSSCHECK_20260926.md`.

Owner sequencing:
1. work next on the per-application exclusions/routing capability;
2. stabilize and accept its functional behavior first;
3. before publishing a release that contains that new capability, unify the interface across release-target platforms.

Acceptance direction:
- use the mobile UI as the common Arvectum design-language seed;
- do **not** ship the current phone/Catalyst geometry unchanged on desktop;
- use one stateful Connect/Connecting/Disconnect primary action on every platform;
- keep connection status and active profile in one close visual cluster;
- establish the same top-level information model: Home, Profiles, Activity/Diagnostics, Settings;
- move expert/maintenance actions (connection test, diagnostics, network repair, autostart) out of the primary Home hierarchy;
- preserve touch-first navigation on Android/iOS and desktop-density/keyboard/pointer/native-menu behavior on Windows/Linux/macOS;
- preserve platform routing/recovery/security semantics; UI parity must not weaken backend guarantees;
- require physical visual/interaction acceptance on every platform targeted by the release.

Implementation is now in progress on the Owner-selected APL-UI-001 branch. Exact-head platform CI and physical visual/interaction acceptance remain mandatory before public release.

## P9 — macOS direct production distribution — DONE / PUBLISHED v0.2.16

- Developer ID Application signing is operational on the Arvectum-controlled Mac mini.
- ARM64 and Intel production DMGs were promoted from exact main, signed, Apple-notarized/stapled and Gatekeeper-verified.
- v0.2.16 publishes both notarized macOS DMGs alongside Windows/Linux artifacts.
- GitHub/GitVerse payload parity and release evidence are complete.
- Direct v0.2.16 is immutable and remains a separate supported distribution channel from the Mac App Store lane.

Do not reopen this task unless a later material direct-distribution signing/package change requires fresh acceptance.

## P9A — macOS App Store 0.2.17 + Help UX — SUBMITTED / WAITING FOR REVIEW / PR #175

Completed: isolated sandboxed ARM64 Catalyst + PacketTunnel lane; contract tests 9/9; provisioning/signing/archive/export/Apple validation/upload PASS; build 1 VALID / APP_STORE_ELIGIBLE; metadata, 4+ rating, Data Not Collected privacy, 175 territories and Mac screenshots complete; mandatory offline Help physically accepted; Packet Tunnel E2E physically accepted with HTTPS 200 and zero tunnel errors; version 0.2.17 build 1 submitted on 2026-09-26 and now WAITING FOR REVIEW.

Boundary: direct v0.2.16 remains immutable and separate. Do not rebuild, re-upload, withdraw or resubmit the Mac App Store version while review is pending unless Apple returns a concrete issue or the Owner requests a change.


## P10 — Russian Software Register dossier / external filing — DOSSIER DONE, SUBMISSION HOLD

### Repository dossier — DONE

APL-REG-001D was merged by PR #95 with final checkpoint PR #96.

Prepared under `docs/registry/` for `v0.2.9` / class `02.02 — Программы обслуживания`:

- application-field worksheet;
- Rule 1236 matrix;
- functional characteristics;
- install/operation/removal/recovery manual;
- support/maintenance statement;
- lifecycle/infrastructure statement;
- licensing/price statement;
- expert verification procedure;
- private-evidence checklist;
- pre-submission audit.

Focused dossier tests: `6/6 PASS`. Exact-head GitHub workflows: `10/10 SUCCESS`.

### External filing — PRE-SUBMISSION / HOLD

Before signing/submission, close all real gates:

1. P5 rights/corporate evidence;
2. applicable foreign-payment/accounting evidence;
3. P6 physical Russian lifecycle proof;
4. factual Russian support/modification entity/person and official contacts;
5. final exact-`v0.2.9` Russian-GUI visual review;
6. current corporate facts and signer authority;
7. qualified electronic signature / УКЭП;
8. live law/classifier/portal recheck immediately before filing.

Automation must never sign or submit the application.

Under the official baseline rechecked 2026-09-17, the two-trusted-OS condition for class 02.02 starts on **2027-01-01**. Existing Astra + RED OS physical acceptance is retained as future-proof compatibility evidence; exact-`v0.2.9` reruns remain preferred but are not represented as a current 2026 filing blocker.

## P11 — mobile store stages

### APL-MOB-004 Android monetization/distribution — PLANNED / OWNER-GATED

Free RU/US proxy functionality is implemented separately. Ads/private distribution still require explicit Owner priority and package/update-identity decision; no ad SDK/private-release infrastructure is authorized by the gateway work.

### iOS 0.1.19 — SUBMITTED / WAITING FOR REVIEW

Merged implementation PR: `#135`. Canonical checkpoint: `.agent/checkpoints/APL-IOS-APPSTORE-PUBLISH-20260925.yaml`.

Completed:
- physical iPhone acceptance PASS;
- LLC ARVECTUM organization signing/provisioning complete;
- first-use VPN privacy disclosure + app/PacketTunnel privacy manifests;
- public privacy/support pages;
- final Apple Distribution IPA 0.1.19 build 21 validation PASS;
- upload PASS and processing complete;
- build 21 attached to App Store version 0.1.19;
- required metadata, screenshots, age rating, App Privacy (Data Not Collected), pricing/territories and review information saved;
- DSA trader status recorded Active;
- version submitted to App Review;
- temporary upload/publish API keys revoked and local temporary key material removed.

Current external state: **Waiting for Review / 1 Item Submitted**.

Boundary:
- do not claim the app is publicly live until Apple approves/releases it;
- do not rebuild, re-upload, withdraw or resubmit while review is pending unless Apple returns a concrete issue or the Owner requests a change;
- 0.1.19 contains no ads, analytics, Arvectum cloud backend or per-app routing.

## Maintenance / repository hygiene

- PR #80 — release-evidence workflow maintenance; reconcile with current `main` before merge.
- PR #81/#103/#132/#157 — superseded older APL-REL-016 preparations; PR #161 is the latest substantive but version-stale trust packet to refresh against v0.2.16.
- PR #113 — redundant AppImage closeout branch overtaken by merged PR #112.
- PR #117 — redundant Android 0.1.13 closeout overtaken by merged PR #118.
- PR #120 — superseded continuous-failover development branch overtaken by merged PR #119.
- PR #124 — stale APL-MOB-002 closeout branch; Android APL-MOB-003 is completed/published at 0.1.19 and current-main friend-test work is 0.1.31.
- PR #68 — superseded per-app routing decision preparation; current packet is PR #144.
- PRs #90/#91/#92 — superseded Windows rollback implementations; merged PR #93/#94 and public `v0.2.9` are authoritative.
- PRs #70/#74/#82 — superseded RED OS preparation paths; merged PR #83 is authoritative.

These stale PRs are not product tracks and must not be resumed without reconciliation.

## Current execution view

- **DESKTOP STABLE:** v0.2.16 is public and immutable; exact release SHA `6799297bf1492d352ca9d78a0a49b2adf3345d2a`.
- **DIRECT macOS:** ARM64 + Intel DMGs are Developer ID-signed, notarized/stapled, Gatekeeper-verified and publicly released.
- **MAC APP STORE:** **0.2.17 build 1 submitted / Waiting for Review / PR #175**. Store validation/upload, privacy/screenshots, Help and physical tunnel acceptance are complete.
- **ANDROID PUBLIC:** `android-v0.1.19`.
- **ANDROID FRIEND-TEST:** 0.1.31 merged with live server-backed RU/US locations; no public 0.1.31 release.
- **FREE GATEWAY:** live controlled-test infrastructure with supplier secrets server-side; anti-abuse/quota hardening remains before broad anonymous rollout.
- **APL-MOB-004:** PLANNED / OWNER-GATED.
- **iOS:** **0.1.19 build 21 submitted / Waiting for Review**; no repo action while Apple review is pending absent a concrete review issue.
- **APL-IP-001:** DONE for the exact v0.2.9 filing-evidence object; do not silently re-scope registry evidence to v0.2.16.
- **APL-REL-016:** READY FOR REVIEW REFRESH; latest substantive PR #161 must move to v0.2.16 / first eligible v0.2.17+.
- **PER-APP ROUTING:** PR #144 remains the Owner decision packet; refresh baseline wording to v0.2.16/current-main, then stop at architecture decision.
- **REGISTRY INFRA:** HUMAN BLOCKED on physical Russian sovereign lifecycle proof (#55).
- **REGISTRY FILING:** HUMAN HOLD; private/accounting/support/signature/live-portal evidence remains.

Work-conserving order: do not churn either submitted Apple binary while review is pending; independent safe REVIEW work may refresh APL-REL-016, followed by PR #144. Do not publish Android 0.1.31, broaden the gateway, start MOB-004, choose per-app architecture, or submit registry filings without the required Owner/HUMAN gate.

## Completion discipline

Do not relabel CI as physical-host/device evidence, repository documentation as legal/corporate proof, detached Russian evidence as Microsoft native publisher trust, or automation as Owner/HUMAN approval. Published releases are immutable evidence objects; changed product bytes require a new version.
