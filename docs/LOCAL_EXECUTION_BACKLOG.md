# Arvectum Proxy Launcher — remaining local / human / infrastructure backlog

Updated: 2026-09-21  
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Current stable release: `v0.2.12`

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

Stable macOS DMG is still excluded pending deliberate Developer ID signing/notarization.

## P2 — Astra Linux / Gate R8 — DONE / PHYSICAL PASS

- **DONE** — real Astra Linux Special Edition 1.8/Fly physical-host acceptance.
- **PASS** — install, GUI/runtime, NetworkManager enable/disable, no-proxy sync, exact rollback, autostart, crash recovery, reboot recovery, package lifecycle, diagnostics/privacy and cleanup.
- **DONE** — APL-LNX-011 Firefox system-proxy fix closed by PR #71/#72.
- **CURRENT RELEASE** — `v0.2.9` ships the Astra DEB.

Astra acceptance remains a trusted-OS compatibility evidence record; an exact-`v0.2.9` rerun is future-proof evidence, not a currently represented 2026 filing prerequisite.

## P3 — RED OS / APL-REG-001C — DONE / PHYSICAL PASS

- **DONE** — RED OS 8.0.3 Standard Desktop x86_64 physical acceptance, merged by PR #83.
- **PASS** — clean install and RPM verification, start/stop, byte-exact KDE + NetworkManager rollback, Chromium system-PAC routing, localhost no-proxy, emergency rollback, XDG autostart ownership, diagnostics/no-mutation, full remove/reinstall and final restoration.
- **PASS** — focused RED OS regression suite `62/62`.
- **CURRENT RELEASE** — `v0.2.9` ships the RED OS RPM.

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

Issue: `#30`. Existing review PR: `#132`.

PR #132's substantive research/tests are useful, but its version boundary is stale:
- it treats `v0.2.10` as current;
- it names `v0.2.11+` as the first eligible embedded-signing release;
- public `v0.2.11` and `v0.2.12` have since shipped unsigned.

Current action:
1. refresh/rebase or replace PR #132 against immutable `v0.2.12`;
2. make `v0.2.13+` the first eligible future native Authenticode/public-trust release;
3. re-verify SmartScreen/App Reputation, Smart App Control/Application Control, managed-enterprise trust, CA/B Forum and provider geography requirements;
4. keep Russian detached CryptoPro/Rutoken evidence separate from Microsoft-native publisher trust;
5. stop at Owner review.

Provider/certificate spend, key custody, production signing, packet merge as an approved decision and release remain Owner-reserved.

## P8 — per-application routing — CURRENT PREPARATION / OWNER DECISION

Current decision PR: `#144`. Stale predecessor PR #68 is superseded.

PR #144 carries only the refreshed decision packet/checkpoint and does not replay obsolete agent metadata. It recommends, without approving, an Arvectum-owned WFP ALE callout + privileged service + local proxy path.

Current gate:
1. reconcile PR #144 wording/assumptions from the v0.2.10 saved-or-Arvectum baseline to immutable `v0.2.12` plus current-main recovery semantics;
2. preserve separate WFP ownership/foreign-resource non-ownership and the APL-REL-016 signing dependency;
3. Owner/Product Owner selects or rejects the production architecture;
4. only after approval implement the privileged enforcement slice;
5. require real Windows host recovery/security acceptance;
6. release only as a new version.

Exact-head repository checks on #144 are green. No architecture is approved by that fact.

## P9 — macOS production distribution — RECOVERY FIXED / TEST LANE EXISTS / PROD DEFERRED

- APL-MAC engineering/acceptance baseline exists.
- `v0.2.10-macos-test.1` and `v0.2.10-macos-test.2` arm64 prereleases exist for dogfood.
- PRs #141/#143 hardened upstream/Safari CONNECT routing.
- PRs #146/#149 resolved the long-sleep regression; final v0.2.12 behavior has physical MacBook acceptance evidence.
- Public desktop v0.2.12 includes the source fix but **does not** publish a macOS DMG.

Remaining production-specific work:
- Apple Developer ID signing/notarization;
- any Apple-specific hardened build-input path still required;
- stable promoted distribution policy.

This remains deferred under the Russia-first priority model.

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

## P11 — later mobile stages

### APL-MOB-004 Android monetization/distribution — PLANNED / OWNER-GATED

Free RU/US proxy functionality is already implemented separately. Ads/private distribution still require explicit Owner priority and package/update-identity decision; no ad SDK/private-release infrastructure is authorized by the gateway work.

### iOS — ACTIVE PERSONAL-USE ENGINEERING / HUMAN GATE

Draft PR: `#135`.

Implemented engineering baseline:
- SwiftUI client;
- NetworkExtension Packet Tunnel + pinned tun2proxy;
- Auto/manual proxy selection, health/failover and optional primary restoration;
- shared Keychain/App Group state;
- HTTP/SOCKS5 and local TLS relay;
- site exclusions;
- branded icon/XcodeGen/reproducible dependency fetch.

Recorded local checks: plutil, XcodeGen, Swift core build and Swift source parsing PASS.

Remaining:
- rebase/reconcile the draft against current main as needed;
- full Xcode/XCTest/device build;
- Apple signing/provisioning;
- physical iPhone install/acceptance.

Boundary: personal-use lane only unless a separate Owner decision admits App Store/public distribution. Do not commit certificates or provisioning profiles.

## Maintenance / repository hygiene## Maintenance / repository hygiene

- PR #80 — release-evidence workflow maintenance; reconcile with current `main` before merge.
- PR #81/#103 — superseded older APL-REL-016 preparations; PR #132 is the current but version-stale trust packet to refresh.
- PR #113 — redundant AppImage closeout branch overtaken by merged PR #112.
- PR #117 — redundant Android 0.1.13 closeout overtaken by merged PR #118.
- PR #120 — superseded continuous-failover development branch overtaken by merged PR #119.
- PR #124 — stale APL-MOB-002 closeout branch; Android APL-MOB-003 is completed/published at 0.1.19 and current-main friend-test work is 0.1.31.
- PR #68 — superseded per-app routing decision preparation; current packet is PR #144.
- PRs #90/#91/#92 — superseded Windows rollback implementations; merged PR #93/#94 and public `v0.2.9` are authoritative.
- PRs #70/#74/#82 — superseded RED OS preparation paths; merged PR #83 is authoritative.

These stale PRs are not product tracks and must not be resumed without reconciliation.

## Current execution view

- **DESKTOP STABLE:** v0.2.12 is public and immutable; exact release SHA `8d9a4e5913fa92b39f0f926004df6f1fd57f3bde`.
- **CURRENT MAIN:** `df4478a70729e20f33b7a0d17476183423955576`, ahead of v0.2.12 because free-gateway/Android 0.1.31 work merged afterward.
- **ANDROID PUBLIC:** `android-v0.1.19`.
- **ANDROID CURRENT FRIEND-TEST:** 0.1.31 merged in #148, free RU/US live, exact-head checks/soak PASS, but no public 0.1.31 release.
- **FREE GATEWAY:** live controlled/friend-test infrastructure with server-side supplier secrets; anti-abuse/quota hardening is still required before broad anonymous rollout.
- **APL-MOB-004:** PLANNED / OWNER-GATED; advertising/private no-ads distribution is separate from free-proxy functionality.
- **APL-IP-001:** DONE for the exact v0.2.9 filing-evidence object; do not silently re-scope registry evidence to v0.2.12.
- **APL-REL-016:** READY FOR REVIEW REFRESH; PR #132 must move to v0.2.12 / first eligible v0.2.13+ before Owner review.
- **PER-APP ROUTING:** PR #144 is the current decision packet; refresh baseline wording to v0.2.12/current-main, then stop at Owner architecture decision.
- **REGISTRY INFRA:** HUMAN BLOCKED on physical Russian sovereign lifecycle proof (#55).
- **REGISTRY FILING:** HUMAN HOLD; private/accounting/support/signature/live-portal evidence remains.
- **MAC:** long-sleep recovery fixed/physically accepted; stable Apple-signed/notarized distribution remains deferred.
- **iOS:** draft PR #135 active as personal-use engineering; signing/device acceptance remains HUMAN.

Work-conserving order for watchdog: first refresh APL-REL-016, then refresh PR #144 to the current v0.2.12 baseline. Do not start MOB-004, public Android 0.1.31 release, broad gateway rollout, iOS signing/App Store work, or external registry submission without the required Owner/HUMAN gate.

## Completion discipline

Do not relabel CI as physical-host/device evidence, repository documentation as legal/corporate proof, detached Russian evidence as Microsoft native publisher trust, or automation as Owner/HUMAN approval. Published releases are immutable evidence objects; changed product bytes require a new version.
