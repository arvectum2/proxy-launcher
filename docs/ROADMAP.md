# Arvectum Proxy Launcher — canonical roadmap

Updated: 2026-10-05
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Canonical branch: `main`  
Current stable product line: 0.2.16 — public release for Windows x64, Astra Linux 1.8 x86-64, RED OS 8.0.3 x86-64, generic Linux x86-64 AppImage and Developer ID-signed/notarized macOS Apple Silicon/Intel DMGs

Status legend: **DONE**, **PUBLISHED**, **CURRENT**, **READY NOW**, **READY**, **IMPLEMENTED**, **PARTIAL**, **HUMAN/LEGAL PENDING**, **STOP-GATE**, **PAUSED**, **DEFERRED**, **FUTURE**.

## 0. Repository authority and release baseline

- **DONE** — source/history/tags were recovered into `arvectum2/proxy-launcher`; `main` is the canonical integration branch.
- **DONE** — current governance, installer/support and repository-identity references are normalized to the canonical slug without rewriting historical provenance.
- **DONE** — GitVerse mirror logic is owner-independent on the GitHub side and current GitHub/GitVerse release mirroring is operational.
- **DONE** — exact-SHA GitHub Actions evidence was rebuilt in the canonical repository for Windows portable, Windows installer/Gate R6, SAST, SBOM, provenance and release evidence.
- **DONE** — `main` protection is governed by the active `Protect main` ruleset; PR + required `build` enforcement and negative merge acceptance have been proven.
- **DONE** — stale Windows PowerShell 5.1 signing-chain encoding contract was corrected in PR #43; `Windows Russian-first Production Signing` is green again without changing production signing behavior.
- **MIGRATION CLOSED** — the `arvectum1 -> arvectum2` repository migration is no longer an active project gate.

Historical repository identifiers remain valid only inside explicit provenance, closed acceptance, immutable baseline or historical workflow material. They are not current operational authorities.

## 1. Current stable product line

- **CURRENT / PUBLISHED — v0.2.16** (published 2026-09-25): Windows x64 Setup + portable ZIP, Astra Linux x86-64 DEB, RED OS 8.0.3 x86-64 RPM, generic Linux x86-64 AppImage, Developer ID-signed/notarized macOS Apple Silicon + Intel DMGs, plus SHA256SUMS.txt.
- **EXACT RELEASE OBJECT** — immutable v0.2.16 annotated tag/release points to `6799297bf1492d352ca9d78a0a49b2adf3345d2a`; GitHub asset digests, exact-SHA Release Evidence Package, Developer ID/notarization evidence and GitVerse public payload parity were verified.
- **POST-RELEASE METADATA ONLY** — any main commits after the v0.2.16 tag are documentation/checkpoint reconciliation only unless a later product task explicitly changes the product version.
- **v0.2.11** (published 2026-09-20) carried the Windows PAC/WPAD isolation fix and macOS Safari/CONNECT routing hardening.
- **v0.2.12** publishes the verified macOS long-sleep recovery and Android long-sleep/foreground VPN reconciliation while preserving immutable v0.2.11.
- **CURRENT SAFETY CONTRACT** — Windows rollback/recovery retains saved-or-Arvectum ownership/fail-closed semantics; Astra/Fly and RED OS/KDE real-host acceptance remain valid unless a material platform/recovery change requires rerun.
- **DONE / MAC PHYSICAL** — the v0.2.12 macOS long-sleep fix has real MacBook acceptance evidence: roughly 96 seconds Maintenance Sleep recovered without disabling APL or restarting the browser, with fresh CONNECT 200 after wake.
- **DONE / MAC TEST DISTRIBUTION** — `v0.2.10-macos-test.1` and `v0.2.10-macos-test.2` arm64 prereleases exist for dogfood. They are not the stable public macOS lane and do not imply Developer ID/notarization.
- **HISTORICAL ANCHOR** — v0.2.5 remains the first physically sealed Windows CFA-safe baseline and immutable provenance anchor.
- **HISTORICAL PROGRESSION** — v0.2.6 Windows+Astra; v0.2.7 RED OS; v0.2.8 Linux recovery hardening; v0.2.9 Windows recovery symmetry; v0.2.10 AppImage promotion; v0.2.11 PAC/WPAD + Safari routing fixes; v0.2.12 long-sleep recovery.

Current canonical main verified before this roadmap update: 6b3a9c4a2b18585487a3df0504d9b62b0110a292.
## 2. Russian-first release trust and Windows public trust

- **DONE** — APL-REL-010 real Rutoken/CryptoPro detached-signature POC and the Russian release-evidence architecture.
- **DONE / HISTORICAL EVIDENCE** — company УКЭП/CryptoPro remains RELEASE-EVIDENCE-ONLY; it is not Microsoft Authenticode/SmartScreen publisher trust.
- **DONE** — APL-REL-011/012/013 release manifest, verification UX and fail-closed Russian production release gate.
- **CURRENT PUBLIC RELEASE** — v0.2.16 is published without native Windows Authenticode; macOS Developer ID/notarization is a separate platform trust path.
- **READY FOR REVIEW REFRESH — issue #30, PR #161** — #161 is the latest substantive APL-REL-016 packet, but it became stale after later unsigned releases. With immutable v0.2.16 now public, refresh/rebase from current main and make **v0.2.17+** the first eligible future native Authenticode/public-trust release.
- **SUPERSEDED REVIEW HISTORY** — PRs #132 and #157 preserve older v0.2.10/v0.2.12-era preparation but are not the current packet.
- **OWNER GATE** — after refresh, provider/certificate selection, spend, key custody, packet merge as an approved decision, production signing and release remain Owner-reserved.
- **RULE** — never retrofit embedded signing into an immutable published release; every trust change belongs to a new version.

## 3. IP / legal / sovereignty

- **DONE** — APL-IP-002 platform sovereignty audits.
- **DONE** — APL-IP-003 canonical source refactor, Slices 1–23.
- **DONE** — APL-IP-004 promoted-artifact third-party license bundle engineering.
- **[Web] DONE — post-APL-IP-004 review reconciliation** — historical governance anchor remains candidate `ef9846e151a2e4e7046169e0787603969018cc97`; later v0.2.9 filing evidence does not rewrite that historical review.
- **HISTORICAL CONTRACT — CONDITIONAL / POST-APL-IP-004 ENGINEERING RECONCILED / HUMAN-LEGAL PENDING.** This phrase is retained solely for the historical clean-IP/legal-baseline contract; it does not mean the current registry filing-evidence packet is blocked.
- **[Web after explicit APPROVED] — create governed clean-IP baseline/tag** only if a distinct clean-IP/legal-baseline action is deliberately reopened.
- **DONE FOR CURRENT FILING EVIDENCE — APL-IP-001 / v0.2.9.**
- **HISTORICAL ANCHOR** — v0.2.5 remains the first physically sealed Windows CFA-safe IP/provenance baseline; its source/tag/artifact evidence and 2026-09-14 packet are preserved and are not rewritten.
- **DONE / EXACT-OBJECT ENGINEERING** — accepted v0.2.9 source commit `ca7c1019...`, source tree `55f2d50f...`, immutable tag commit `d13d9dac...` and promoted release-package digests are governed.
- **DONE / EXACT-TREE EVIDENCE** — provenance run `35255499712` and CycloneDX SBOM run `35255499669` bind to the exact released source tree.
- **DONE / ENGINEERING DRIFT RECONCILIATION** — material v0.2.5 -> v0.2.9 evolution is classified across Astra/Linux, RED OS/RPM, Linux recovery and Windows rollback-ownership slices.
- **DONE / OWNER FACTS** — the actual 2026-09-14 private sole-participant/rightsholder decision was reviewed; it identifies Arvectum Proxy Launcher without a version number, transfers the exclusive right in full and authorizes modification/reworking. Current Rospatent, corporate/Russian-control and human creative-control facts were confirmed by the Owner.
- **v0.2.9 HISTORICAL SCOPE** — Windows Setup + portable, Astra DEB and RED OS RPM. Owner directive 2026-09-18 separately admits AppImage for the next release; immutable v0.2.9 evidence is not rewritten.
- **PROCESS CORRECTION** — the previously prepared R-1B two-party/self-signing future-rights agreement is not a mandatory APL-IP-001 or registry-filing step. It is retained only as optional external legal hardening for the residual question of later human-authored copyrightable contributions. Do not reintroduce it as a blocker without new Owner/legal input.
- **RULE** — repository evidence is not a legal opinion. If the registry/expert or external counsel specifically requests a stronger chain-of-title instrument for later contributions, handle that as a targeted legal-hardening task rather than per-version compliance ritual.

Canonical current records: `docs/APL_IP_001_V0_2_9_SIGNOFF.md`, `docs/evidence/APL_IP_001_V0_2_9_CANDIDATE_RECONCILIATION_2026-09-18.md`, `docs/evidence/APL_IP_001_V0_2_9_OWNER_FACT_CONFIRMATION_2026-09-18.md`. Historical v0.2.5 records remain evidence.

## 4. Linux / Astra Linux

- **DONE** — APL-LNX-001..009 engineering: environment detection, NetworkManager preflight, capability/PolicyKit UX, autostart, diagnostics, Debian packaging and CI acceptance.
- **DONE / PHYSICAL PASS** — APL-LNX-010 / Gate R8 on Astra Linux Special Edition 1.8/Fly. Real-host evidence covers install, GUI/runtime, NetworkManager enable/disable, exact rollback, crash/reboot recovery, autostart, package lifecycle, diagnostics/privacy and cleanup.
- **DONE** — APL-LNX-011 fixed Firefox system-proxy behavior on Astra/Fly and was closed by PR #71/#72.
- **CURRENT RELEASE** — v0.2.16 publishes Arvectum-Proxy-Launcher-0.2.16-astra-linux-amd64.deb; v0.2.9 remains the governed registry-filing evidence baseline.
- **PROMOTED LANE** — Debian .deb remains the preferred Astra/Linux package.
- **PROMOTED FOR NEXT RELEASE** — the x86_64 AppImage lane uses the same canonical Linux frozen executable, hash-pinned appimagetool/type-2 runtime, embedded runtime/third-party notices, exact-main CI reuse and release checksum coverage. `v0.2.9` remains unchanged.
## 5. Russian Software Register / APL-REG-001

This is an active compliance/filing workstream, but repository dossier preparation is now substantially complete.

- **DECIDED WORKING CLASS** — 02.02 — Программы обслуживания, subject to live classifier/law recheck immediately before filing.
- **DONE / PHYSICAL** — first trusted-OS acceptance record: Astra Linux SE 1.8.
- **DONE / PHYSICAL** — second trusted-OS acceptance record: RED OS 8.0.3 Standard Desktop x86-64, merged in PR #83.
- **DONE** — APL-REG-001D filing-grade documentation dossier for v0.2.9 merged in PR #95; final checkpoint PR #96 records 6/6 focused dossier tests and 10/10 exact-head GitHub workflows successful.
- **CURRENT LEGAL TIMING BASELINE** — under the official baseline rechecked on 2026-09-17, the two-trusted-OS condition for class 02.02 starts on **2027-01-01**. Existing Astra/RED acceptance is retained as future-proof compatibility evidence; exact v0.2.9 reruns are preferred but are not represented as a current 2026 filing prerequisite.
- **PRE-SUBMISSION / HOLD** — external filing is blocked on real HUMAN/PRIVATE/PHYSICAL evidence: exclusive-right/corporate/Russian-control chain, applicable foreign-payment/accounting evidence, APL-REG-001B physical sovereign lifecycle proof, factual Russian support/modification contacts, final exact-v0.2.9 Russian-GUI visual review, signer authority/qualified electronic signature, and a live law/portal recheck.
- **HARD STOP** — automation must not sign or submit the Ministry/registry application or ingest УКЭП/private-key material.

Canonical dossier: docs/registry/. Canonical pre-submission gate: docs/registry/APL_REG_001F_PRE_SUBMISSION_AUDIT.md.
## 6. macOS

- **DONE** — APL-MAC-001..008 engineering/acceptance track and Gate R9 evidence retained.
- **DONE / TEST DISTRIBUTION** — arm64 prereleases `v0.2.10-macos-test.1` and `v0.2.10-macos-test.2` were published for dogfood and mirrored with checksum parity.
- **DONE / ROUTING + WAKE HARDENING** — PRs #141/#143/#146/#149 plus later v0.2.14/v0.2.15 recovery work close the current direct-distribution routing/sleep baseline.
- **PRODUCTION DISTRIBUTION — DONE / PUBLISHED v0.2.16** — exact-main ARM64/Intel packages were promoted through the Arvectum Mac mini, signed with Developer ID Application, Apple-notarized/stapled, Gatekeeper-verified, published and mirrored with payload parity.
- **NEXT DIRECT DESKTOP RELEASE — MANDATORY macOS recovery inclusion (v0.2.17+).** Carry forward PR #203 (reserved wake-refresh fail-closed sentinel recovery) and PR #207 (exact-endpoint HTTP/HTTPS enable-bit drift recovery). Release acceptance must physically verify: APL start → induced exact-endpoint enable-bit drift → rollback exit 0 → all saved network services match the pre-APL snapshot → direct and ordinary HTTPS succeed → legacy 127.0.0.1:1080/8082 tunnel remains untouched. Do not ship the next direct macOS desktop build from a source point older than merge commit 46aef7ecfd165aa03145d2a74d4aba1ba44d972d.
- **MAC APP STORE — RESUBMITTED / WAITING_FOR_REVIEW — v0.2.17 build 3.** The Store lane remains separate from immutable direct v0.2.16.
  - Initial build 1 was submitted on 2026-09-26 and rejected on 2026-09-28 under Guidelines 2.1.0 App Completeness and 2.4.5 Hardware Compatibility.
  - PR #223 merged the binary remediation at `ad09b2393def6c498daa8d67d2439b1d1aac9502`: passive launch no longer mutates Network Extension preferences, Store help no longer advertises GitHub/self-update behavior, and the Catalyst minimum was corrected.
  - Build 2 remains intentionally unused because its uploaded metadata reported macOS 12.0 minimum.
  - Build 3 remains the accepted binary: ARM64 Mac Catalyst + PacketTunnel, `LSMinimumSystemVersion=13.0`, Apple validation PASS, physical passive-launch smoke PASS, `usesNonExemptEncryption=false`.
  - Apple returned a second review response on 2026-10-01 covering Guideline 5.2.5 product naming plus Guideline 2.1 reviewer access and VPN/data-handling questions. These were metadata/reviewer-information issues, not a new binary defect.
  - On 2026-10-02 the App Store name was changed to `Proxy Launcher by Arvectum`; App Review Information was updated with working reviewer-access instructions and direct VPN/data answers; a reviewer reply was sent; the existing build 3 review item was resolved and resubmitted without rebuilding.
  - **CURRENT ASC STATE:** app version 0.2.17 (3) and its review submission are `WAITING_FOR_REVIEW`. Do not rebuild, re-upload or bump the build unless Apple identifies a concrete new binary issue.
- **MANDATORY HELP UX — DONE / PHYSICAL PASS.** The standard macOS Help item opens bundled offline help.
  - Direct Developer ID builds may expose GitHub/release links appropriate to direct distribution.
  - Mac App Store builds must remain useful offline and rely on App Store update semantics; the build-3 remediation removes competing GitHub Releases/self-update language from the Store help flow.
  - Core offline sections remain: **Getting Started**, **status meanings**, **proxy formats**, **Troubleshooting**, **About & Privacy**.
  - No Store build may ship a competing self-updater.
- **OPTIONAL FUTURE** — keep `.app`/DMG as the normal direct macOS distribution lane; add a separate portable form only if it provides real benefit without weakening recovery/update semantics.

## 7. Per-application routing — application exclusions and desktop enforcement

- **DONE** — APL-ROUTE-001 platform-neutral routing-rule model.
- **DONE** — APL-ROUTE-002 per-platform feasibility matrix.
- **AUTONOMOUS COMPLETE / LOCAL-NATIVE PENDING** — APL-ROUTE-003 Windows read-only/control-plane prototype.
- **DONE** — APL-ROUTE-004 durable ownership/recovery/security journal.
- **APPLICATION EXCLUSIONS CONTROL PLANE — IMPLEMENTED.** PR #183 added deterministic application-exclusion persistence/capability semantics plus Android live enforcement through `VpnService.Builder.addDisallowedApplication`.
- **ANDROID UI / CURRENT MAIN — 0.1.38 / versionCode 39.** The accepted adaptive/profile/application-exclusion baseline is retained; PR #221 layers the current public/private Android distribution flavors on top without regressing manual profiles, Auto, site exclusions or application exclusions.
- **iOS CONSUMER PATH — SHORTCUTS AUTOMATION.** Native unmanaged consumer iOS cannot truthfully offer arbitrary Per-App VPN selection; PRs #185/#187/#189 provide the supported consumer workaround using APL App Intents + Shortcuts Opened/Closed automations. Managed/MDM Per-App VPN remains a different future capability.
- **WINDOWS PRODUCTION ARCHITECTURE — OWNER SELECTED / IMPLEMENTED / PHYSICAL PASS.** Production per-application routing uses the official signed WinDivert 2.2.2 stack plus the narrow Arvectum routing service and local proxy. PR #241 merged the production implementation to main at `61fcf2c0fae1e1b0ca93b2271eb3b907f49db352`; PR #243 merged the physical-installer compatibility fix at `f61f506761c79a882470ebdbf9f34a1aab9baf28`. The Arvectum-owned custom WFP callout path is lab-only and is not the production architecture.
- **WINDOWS PHYSICAL E2E — DONE.** Exact-head Windows CI passed for installer, portable, WinDivert production and public-trust gates. Physical `ArutyunovNS` acceptance proved fresh install, GUI-selected `curl.exe` DIRECT vs unselected `powershell.exe` PROXY, live rule removal/re-add, disconnect/reconnect, forced-runtime-crash rollback and active-session reboot recovery. The production path does not require an Arvectum-owned Microsoft kernel-driver signing certificate.
- **RELEASE BOUNDARY.** These merges update current main only. Published desktop v0.2.16 remains immutable and must not be represented as containing this later Windows per-app implementation. Shipping it requires the next explicit Windows desktop release task and release acceptance.
- **ANDROID ACCEPTANCE BOUNDARY** — implementation and UI are merged, but do not invent the dedicated public-IP bypass proof if it has not been recorded separately.
- **APL-UI-001 GATE — DONE.** The cross-platform Adaptive UI was merged in PR #193 by explicit Owner decision; the remaining unavailable physical-platform acceptance was waived for that merge only and is not claimed as performed.

## 7A. Cross-platform Adaptive UI — APL-UI-001 — DONE / MERGED

Design decision source: `docs/APL_UI_UX_CROSSCHECK_20260926.md`.

- Shared navy/mint tokens, profile/exclusion language, connection-state semantics and one stateful primary Connect/Disconnect action are implemented across supported UI families.
- Mobile remains touch-first; desktop uses compact sidebar/desktop composition and native platform conventions.
- Top-level information model is Home, Profiles, Activity/Diagnostics and Settings.
- macOS recovery-state Home CTA was corrected during physical review.
- Focused desktop/UI regression suite passed 53/53; exact-head cross-platform/security CI was green.
- PR #193 merged on 2026-09-27 after explicit Owner instruction. Unperformed host-specific acceptance is not relabeled as PASS.

## 7B. Universal connection input and managed configuration — APL-CONNECT-001 — FUTURE / PRODUCT-APPROVED

**Product principle:** APL should accept whatever connection material the user already has and keep protocol complexity out of the primary UX. The primary action remains one simple **Add connection / Connect** flow; protocol names and routing internals belong in detected details or an Advanced section.

- **ORDINARY PROXY — RETAIN CURRENT SIMPLE PATH.** Accept `host:port`, `host:port:login:password`, URL-form proxy credentials and the existing manual host/port/login/password fields. Preserve current APL Auto transport behavior across HTTP CONNECT, SOCKS5 and TLS-to-proxy HTTPS instead of forcing the user to select a protocol.
- **VPN LINK / KEY / CONFIG IMPORT — NEW.** Add paste/clipboard, file, QR and deep-link ingestion with deterministic scheme/config detection. Do not label arbitrary opaque text as supported until the corresponding engine can actually connect with it.
- **FIRST ADVANCED FULL-TUNNEL TARGET — VLESS + REALITY.** This is the preferred first VPN-protocol expansion because it matches the planned Arvectum VPS/VLESS+Reality infrastructure and gives Marketplace-issued configurations a native APL path. Keep VLESS/Reality details hidden by default after import.
- **SECONDARY ADVANCED TARGETS — DEMAND DRIVEN.** Evaluate WireGuard/AmneziaWG next; Shadowsocks, Trojan, VMess and Hysteria2 remain later compatibility candidates rather than reasons to turn the main UI into an Xray/sing-box control panel.
- **MTPROTO — TELEGRAM-SPECIFIC CONNECTION TYPE.** Accept manual `server + port + secret` plus standard Telegram proxy links (`tg://proxy...` / `t.me/proxy...`). Treat MTProto truthfully as a Telegram-specific proxy profile: APL may store/manage it and hand it off/open it in Telegram, but must not present MTProto as a device-wide VPN transport.
- **QR / CLIPBOARD / DEEP LINK — REQUIRED IMPORT SURFACES.** A user receiving a supported proxy/VPN/MTProto configuration should be able to scan, paste or open it in APL without retyping credentials.
- **SUBSCRIPTION / MANAGED PROFILE — FUTURE.** Support a URL-backed managed connection collection with bounded automatic refresh, explicit last-refresh/error state and safe rollback to the last known-good configuration. This is the preferred delivery mechanism for Arvectum-managed or third-party provider profiles.
- **MARKETPLACE ZERO-CONFIG DELIVERY — FUTURE.** After purchase, the issued connection should appear in APL automatically; the normal customer should not need to see or copy host/port/login/password or VLESS internals unless they explicitly request/export them.
- **QUICK ACTIONS — FUTURE UX.** Provide connect/disconnect/toggle through platform-appropriate Shortcuts, widgets or Control Center/quick settings where supported, while preserving the existing iOS Shortcuts application-routing workflow.
- **KILL SWITCH — FUTURE / CAPABILITY-GATED.** Expose only on platforms/modes where APL can guarantee fail-closed full-tunnel semantics. Do not use the label for ordinary desktop system-proxy mode unless non-APL direct traffic is actually blocked.
- **LOCAL-FIRST SECRET HANDLING — REQUIRED.** Imported credentials/keys remain in platform secure storage (Keychain/Keystore or equivalent) and must not be uploaded to Arvectum merely because the user pasted or scanned them. A managed Marketplace/subscription flow may contact the issuing backend only as explicitly required to provision/refresh that managed profile.
- **EXPORT/SHARE SAFETY — REQUIRED.** Any export/share action containing secrets must be explicit, preview what will be exposed and never leak credentials through logs, analytics, crash reports or ordinary diagnostic bundles.

### APL-CONNECT-001 staged delivery

1. **Stage A — universal importer shell:** normalize proxy text/URLs, QR, clipboard and deep-link entry; add MTProto profile detection + Telegram handoff; keep current HTTP/SOCKS/HTTPS engines unchanged.
2. **Stage B — VLESS + Reality:** select/pin the engine, implement cross-platform secure profile storage and full-tunnel connection path, then physically validate mobile and desktop behavior before claiming support.
3. **Stage C — managed subscriptions:** signed/validated remote profile refresh with last-known-good rollback, explicit provider/source identity and no silent downgrade to an insecure transport.
4. **Stage D — Marketplace zero-config:** purchase/provision/refresh integration so an Arvectum-issued connection becomes usable in one tap.
5. **Stage E — compatibility expansion:** WireGuard/AmneziaWG first, then additional protocols only when demand/partner interoperability justifies their maintenance cost.

**Anti-clone rule:** competitor breadth is input for compatibility, not the product identity. APL remains optimized for the shortest path from credentials/key/QR to a working connection; advanced routing engines, GeoIP/Geosite rules, raw JSON and protocol diagnostics stay out of the default flow.

## 7C. macOS application exclusions — APL-MAC-PERAPP — FUTURE / PRODUCT-APPROVED

**Goal:** bring real application exclusions to macOS where technically supportable: selected applications use **DIRECT** while other traffic follows the active APL proxy/VPN route, with the same understandable user model as Windows/Android.

- **DIRECT DEVELOPER ID PATH — PRIMARY CONSUMER TARGET.** Treat arbitrary consumer per-app exclusions as a separate macOS networking architecture task, not as a small extension of the current system-proxy/PacketTunnel implementation. The feasibility prototype must choose a supported Network Extension/System Extension design that can attribute flows to their originating application and selectively route them DIRECT or PROXY.
- **MAC APP STORE PATH — CAPABILITY-GATED.** Do not promise arbitrary unmanaged-consumer per-app selection in the Store build. Apple's native `NEAppRule` / per-app VPN path is treated as managed/MDM capability unless a later App Store-specific feasibility review proves a supported consumer design. Store UI must hide unsupported controls rather than emulate them inaccurately.
- **IDENTITY / HELPERS.** Application matching must survive ordinary app updates and handle helper/tool processes deliberately; matching must use stable application identity where possible rather than ephemeral PID-only rules.
- **SAFETY / RECOVERY.** A per-app implementation must preserve APL's ownership journal and rollback discipline, fail safely after crashes, sleep/wake and reboot, and never strand macOS networking or overwrite unrelated proxy/VPN state.
- **UX PARITY.** When supported, expose the same simple model used elsewhere: user picks applications to bypass the proxy, the list shows capability/state clearly, and changes apply through a controlled reconnect without surfacing low-level routing internals.

### APL-MAC-PERAPP staged delivery

1. **Stage A — feasibility / flow attribution:** on a Direct Developer ID test build, prove reliable source-application identification and a real split such as Safari **DIRECT** while another selected test application remains **PROXY** (and vice versa), including helper/tool process behavior.
2. **Stage B — recovery/security:** validate rule changes, disconnect/reconnect, forced runtime failure, sleep/wake, reboot, app update/removal, stale identity handling and exact rollback of APL-owned network state.
3. **Stage C — product UI:** add installed-application selection and exclusions UI aligned with Windows/Android, with capability-gated messaging for unsupported Store/managed contexts.
4. **Stage D — production Direct release:** sign/notarize the required app/system extension components, run physical macOS release acceptance, document uninstall/rollback, and ship only in a new Direct desktop release.
5. **Stage E — managed/MDM option:** if enterprise demand justifies it, add a separate managed `NEAppRule`/Per-App VPN configuration path. Do not conflate this with ordinary consumer App Store functionality.

**Release boundary:** this track is approved for the roadmap but is **not started** and is not part of published v0.2.16 or the current Mac App Store 0.2.17 build 3 review binary. It must not trigger a rebuild/resubmission of the Store candidate while Apple review is pending.

## 7D. International-traffic cost-aware routing — APL-TRAFFIC-001 — FUTURE / PRODUCT-APPROVED / RESEARCH

**Research trigger (2026-10-05):** Russian authorities and mobile operators are reported to be discussing possible charging for high-volume international traffic in 5G networks. Treat the reported **50 GB** threshold and the technical accounting model as provisional until an official rule, tariff methodology or operator implementation is published.

**Product objective:** make APL capable of choosing an economically efficient route without exposing routing complexity to the user. The capability must remain useful independently of any specific 5G charging rule.

- **MULTI-HOP ROUTING — NEW.** Support a provider-neutral chain such as `client -> RU ingress -> foreign exit -> destination`, with health, latency, capacity and price attributes for each hop.
- **COST-AWARE ROUTER — NEW.** Extend Smart Supplier Router so it can compare direct foreign proxy/VPN routes with composed ingress+exit routes and select by availability, quality, latency, price and policy.
- **DIRECT-RU SPLIT — RETAIN.** Russian destinations may remain DIRECT while selected foreign destinations/applications use the configured route; do not turn the whole product into an always-on full-tunnel requirement.
- **PROVIDER-OWNED INFRASTRUCTURE FIRST.** For marketplace design, prefer third-party RU ingress and foreign exit providers so APL remains software/router/marketplace rather than automatically becoming the operator of the transit infrastructure.
- **ARVECTUM-OWNED RU GATEWAY — LEGAL STOP-GATE.** Do not provision or publicly offer an Arvectum-owned Russian traffic gateway until communications/data-processing/licensing and traffic-responsibility implications are separately reviewed.
- **5G/LTE UX — CONDITIONAL.** If an enacted rule applies only to 5G, APL may show usage/context guidance and explain an OS-level LTE option where the platform permits it. Do not claim that APL can programmatically force radio mode on platforms that do not expose that capability.
- **REGULATORY INPUT, NOT EVASION.** Do not implement DPI camouflage, billing-counter manipulation, traffic misclassification or a feature marketed as tariff circumvention. Re-evaluate the route model against the exact official accounting definition before implementation.
- **MEASUREMENT BEFORE PRODUCTIZATION.** When rules become concrete, build a lab matrix across major operators: what endpoint is visible to the operator, how traffic is classified, whether roaming/IPv6/CDN/private relay paths differ, and whether RU-ingress traffic is actually accounted as domestic.
- **FAILOVER / SAFETY.** Multi-hop must degrade predictably: explicit route health, bounded reconnect, no secret leakage, deterministic rollback to the user's prior routing state, and no silent switch from a policy-constrained route to an unapproved one.

Staged delivery:
1. **Stage A — regulatory/technical research:** capture the official rule/methodology and operator implementation; determine exactly what is metered.
2. **Stage B — provider-neutral multi-hop core:** route graph, ingress/exit contracts, health/capacity/price metadata and deterministic selection.
3. **Stage C — lab validation:** real mobile-network measurements for DIRECT vs foreign exit vs RU-ingress→foreign-exit, including IPv4/IPv6 and 5G/LTE where available.
4. **Stage D — product UX:** simple route mode, usage/cost hints, diagnostics and explicit advanced details without protocol jargon in the primary flow.
5. **Stage E — marketplace composition:** supplier auction for ingress and exit capacity only after legal/commercial review and measured benefit.

**Execution boundary:** product-approved research track only. It is not added to the active execution queue and does not reactivate paused APL-NODE-001 or Arvectum Network infrastructure work.

## 8. Mobile applications

### Android — GitHub public 0.1.19 / current-main + RuStore candidate 0.1.38 (39)

- **GITHUB/GITVERSE PUBLIC BASELINE — android-v0.1.19.** This remains the latest published Android release in those channels until a separate publication task creates a later release.
- **CURRENT MAIN — 0.1.38 / versionCode 39.** PR #221 merged the combined RuStore source to main at `676a987105d8f01b8ed32db8b500b58a26e74542`.
- **PUBLIC FLAVOR — ADS ENABLED.** The public flavor includes Yandex Mobile Ads App Open integration using RuStore block `R-M-20130429-1`.
- **PRIVATE FLAVOR — AD-FREE.** A distinct private flavor/package identity is present in the same codebase and does not include the ad integration; separate private distribution remains a delivery concern, not a second divergent application.
- **NO FRIEND/FREE PROFILES IN THE PUBLIC APP.** PR #221 removed the friend/free gateway UX, `FreeGatewayClient`, free-session refresh/recovery behavior and obsolete persisted free selection from the Android public path.
- **CORE USER FEATURES RETAINED.** Manual user-supplied proxy profiles, Auto across user profiles, site exclusions, application exclusions, accepted adaptive UI fixes and VPN recovery behavior remain.
- **RUSTORE — SUBMITTED / WAITING FOR MODERATION.** Version 0.1.38 (39), package `ru.arvectum.proxylauncher`, production-signed APK SHA-256 `21519775dd098fba2c2389ced34e5e991bf3335b6a414af3561b298515f8d572`, audience 100%. Publication mode is **Manual after approval**.
- **HISTORICAL FREE-GATEWAY INFRA.** The prior RU/US friend-test gateway evidence is preserved as historical controlled-test infrastructure, but it is not part of the current public Android client path and must not be reintroduced without an explicit new product task.
- **NEXT GATE.** Wait for RuStore moderation. Any rejection remediation starts from current main; any later GitHub/GitVerse/site 0.1.38+ publication is a separate release task.

### iOS — App Store PUBLISHED: 0.1.36 build 40

- **OLD SUBMISSION REJECTED FOR INFORMATION.** The earlier 0.1.19 new-app submission received Apple Guideline 2.1 Information Needed: physical-device recording plus six product/setup/service/region/material questions.
- **CURRENT SOURCE / REVIEW BINARY — 0.1.36 build 40.** Adaptive UI and Shortcuts-based application routing remain merged; the current review binary is the validated build 40.
- **PHYSICAL DEVICE / REVIEW EVIDENCE PASS.** Current 0.1.36 build 40 has the physical-device review recording already attached to the App Review submission.
- **APP STORE BINARY PASS.** The current build 40 uses the accepted packet-tunnel/App Group/Keychain entitlement scope; no new binary defect is presently identified.
- **APP STORE — PUBLISHED / PUBLIC.** Apple completed review successfully on 2026-10-05; version 0.1.36 build 40 is publicly available in the App Store, including the Russian storefront.
- **PUBLIC METADATA VERIFIED.** Apple exposes ARVECTUM / LLC ARVECTUM, Utilities, 4+, iOS 15.0+, free pricing, `ru.arvectum.proxylauncher.ios`, and Data Not Collected.
- **POST-RELEASE METADATA BACKLOG.** In the next metadata/version update, move Developer Website from GitHub to `arvectum.com`, move the Privacy Policy link to the canonical `arvectum.com` privacy page, and verify/fix App Store localization/language metadata so intended languages are explicitly represented.
- **NO HOTFIX REQUIRED.** These are cosmetic/metadata follow-ups only; do not rebuild solely for them unless a binary/product change is otherwise warranted.

## 9. Currently available workstreams

1. **[Desktop release] v0.2.16 — PUBLISHED / IMMUTABLE.** Windows/Astra/RED OS/AppImage plus Developer ID-signed/notarized Apple Silicon + Intel DMGs.
2. **[Android / RuStore] 0.1.38 (39) — SUBMITTED / WAITING FOR MODERATION.** Public flavor has Yandex App Open ads and no friend/free profiles; private flavor is ad-free. RuStore publication is manual after approval.
3. **[iOS App Store] 0.1.36 build 40 — PUBLISHED / PUBLIC.** Apple approved the submission on 2026-10-05 and the production App Store listing is live. Next work is metadata cleanup only: canonical `arvectum.com` developer/privacy links and localization/language verification.
4. **[macOS App Store] 0.2.17 build 3 — WAITING_FOR_REVIEW.** On 2026-10-02 the new App Review issues were resolved without a binary rebuild: Store name changed to `Proxy Launcher by Arvectum`, Review Notes now include a tested temporary reviewer proxy plus direct VPN/data answers, the reviewer reply was sent, and the existing submission was resubmitted successfully.
5. **[Per-app Windows enforcement] IMPLEMENTED / PHYSICAL PASS ON CURRENT MAIN.** Owner selected official signed WinDivert 2.2.2; PR #241 implementation and PR #243 installer fix are merged and physically validated. Custom WFP remains lab-only. Next gate is an explicit future Windows desktop release; published v0.2.16 is unchanged.
6. **[Windows trust / REVIEW] APL-REL-016 — READY FOR REFRESH.** Latest substantive PR #161 remains version-stale against v0.2.16; future native signing starts with a new release, never by mutating v0.2.16.
7. **[Rospatent / HUMAN] program registration package — PREPARED / WAITING FOR APPLICANT FACTS.** PR #181 tracks the checkpoint; official filing/signature remains human.
8. **[Russian Software Register / HUMAN] dossier prepared on exact v0.2.9; external filing remains on hold for real private/infrastructure/signature gates.**
9. **[Adaptive UI] APL-UI-001 — DONE / MERGED #193.** It remains the shared current UI baseline, not an active implementation task.
10. **[Product expansion / FUTURE] APL-CONNECT-001 — PRODUCT-APPROVED.** Universal connection input: ordinary proxy, VPN link/key/config, MTProto, QR/deep link, managed subscriptions and Marketplace zero-config delivery, staged so protocol complexity stays out of the default UX.
11. **[macOS per-app / FUTURE] APL-MAC-PERAPP — PRODUCT-APPROVED / NOT STARTED.** Primary target is a Direct Developer ID implementation with real source-app attribution and DIRECT/PROXY split routing; Mac App Store behavior remains capability-gated, with managed/MDM Per-App VPN treated separately.
12. **[Backlog-only] APL-NODE-001 and Arvectum Network remain intentionally absent from the primary roadmap and execution queue until explicit Owner reactivation.**

### Repository-hygiene note

Open PRs #81/#103/#132/#157 are superseded Windows-trust preparation history; #161 is the latest substantive stale trust packet. Historical per-app recommendation PRs #68/#144 are superseded by the Owner-selected production WinDivert implementation in merged PR #241 and its physical-installer fix in merged PR #243. Historical rollback/RED OS/mobile closeout branches remain non-authoritative where later merged work exists. Backlog-only paused initiatives are intentionally omitted from this primary roadmap.

### Execution order

- Follow the canonical `.agent/current-task.yaml` for the active user-facing workflow.
- **Android / RuStore:** do not rebuild or resubmit merely because moderation is pending. On RuStore feedback, start a new remediation task from current main and the exact 0.1.38 (39) artifact/source evidence. After approval, publication remains an explicit manual release decision.
- **macOS App Store:** 0.2.17 build 3 is WAITING_FOR_REVIEW after the 2026-10-02 metadata/reviewer-access/data-handling remediation. Wait for Apple feedback; do not rebuild or re-upload unless Apple identifies a new concrete binary issue.
- **iOS App Store:** 0.1.36 build 40 is published. Do not rebuild solely for metadata cosmetics; fold canonical `arvectum.com` links and localization/language cleanup into the next justified App Store update.
- **APL-CONNECT-001:** product direction is approved; start with Stage A universal import/MTProto handoff when this workstream is explicitly prioritized, then VLESS+Reality as the first full-tunnel expansion.
- **APL-MAC-PERAPP:** product direction is approved but implementation is not started; first gate is a Direct Developer ID feasibility prototype proving source-app attribution plus real DIRECT/PROXY split routing. Keep the current Mac App Store build unchanged while it is under review.
- **Windows per-app:** production architecture is settled on official signed WinDivert 2.2.2 and physically accepted on current main. Do not revive the custom-WFP production path without a new Owner decision; do not publish/release the merged feature without a separate Windows release gate.
- **Next direct desktop release:** when prioritized, cut a new release from current main (never mutate v0.2.16), include the merged Windows WinDivert production path and mandatory macOS recovery fixes, rerun platform-specific physical acceptance, then publish as a new version.
- **APL-REL-016:** safe REVIEW refresh remains available when prioritized.
- **Registry/Rospatent:** prepare evidence/forms as authorized, but final external signing/submission remains HUMAN.
- Paused backlog-only initiatives must not consume engineering time until the Owner explicitly restores them to the primary roadmap.
- **Proxy Launcher Watchdog remains outside this roadmap update and must not be enabled or modified by this task.**

## 10. Platform / distribution matrix

| Platform / form | Current state | Next gate |
| --- | --- | --- |
| Windows installer | **PUBLISHED v0.2.16; current main also contains physically accepted WinDivert per-app routing** | Next explicit desktop release + physical release acceptance; Authenticode remains a separate trust track |
| Windows portable | **PUBLISHED v0.2.16; current main has later unreleased Windows routing work** | Next explicit desktop feature release; keep v0.2.16 immutable |
| Astra Linux .deb | **PUBLISHED v0.2.16 / PHYSICAL BASELINE PROVEN** | Rerun physical acceptance only for material platform/recovery or filing changes |
| RED OS .rpm | **PUBLISHED v0.2.16 / PHYSICAL BASELINE PROVEN** | Rerun physical acceptance only for material platform/recovery or filing changes |
| Linux AppImage | **PUBLISHED v0.2.16** | Maintain governed runtime/license/release parity |
| macOS .app / DMG | **PUBLISHED v0.2.16 / DEVELOPER ID + NOTARIZED** | Next direct release: mandatory recovery acceptance; APL-MAC-PERAPP may enter only after its Stage A/B feasibility and safety gates pass |
| macOS Mac App Store | **0.2.17 build 3 WAITING_FOR_REVIEW** | Wait for Apple feedback; no rebuild/re-upload unless Apple reports a new concrete binary issue |
| Android | **GitHub/GitVerse 0.1.19 PUBLIC; current main + RuStore 0.1.38 (39) WAITING FOR MODERATION** | RuStore moderation -> explicit manual publication or targeted remediation; other channels require separate release task |
| iOS | **0.1.36 build 40 PUBLISHED / PUBLIC** | Post-release metadata cleanup: `arvectum.com` developer/privacy links + localization/language verification; rebuild only for a justified binary/product change |

## Completion discipline

Do not substitute CI for physical App Control/Astra/РЕД ОС/mobile-device evidence, detached Russian release evidence for Microsoft native Windows publisher trust, or automation for human/legal decisions. Do not rewrite historical repository identities where they are part of provenance. Do not retarget immutable tags or replace published release assets in place. A documentation-only commit does not create a new product candidate. Current operational references must resolve to `arvectum2/proxy-launcher`.
