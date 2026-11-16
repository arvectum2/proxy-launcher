# APL iOS 0.3.0 — release exit gate (16 November 2026)

## Постоянное решение владельца (подтверждено 01.11, 15.11 и 16.11.2026)

Сохранять действующую работающую рекламную интеграцию и монетизацию iOS без изменений. Это окончательное продуктовое решение, а не вопрос для повторного согласования. Не инициировать повторные исследования SDK, смену модели монетизации, отключение рекламы или пересмотр уже согласованной конфигурации в ходе обычной разработки. Не включать закрытый вопрос в активные блокеры, отчёты или напоминания владельцу. Возвращаться к нему только по новой прямой команде владельца либо при конкретной новой объективной ошибке, непосредственно препятствующей запрошенному действию. Сохранять прежние технические проверки работоспособности рекламы, не подменять реальные результаты и не заявлять непроверенное соответствие требованиям.

Продолжать активную инженерную задачу по .agent/current-task.yaml; исторические исследовательские документы не отменяют этого решения.


Purpose: finish the originally approved consolidated release; avoid repeating
completed physical cases or adding unbounded research to release QA. This
document does not reduce approved scope, enable a production feature, authorize
signing/upload, or establish a release date.

## Verified evidence

* PR #383 exact head 06643dac40611fb4a1e9926275f5b2838625532e: all four
  GitHub checks successful, including mirror, core, unsigned device and Release
  builds. CI run 43875528025.
* Downloaded actual CI unsigned Release ZIP (SHA256
  8a1560c5690d2193a7278b2360747ef5fdced1695416935c52ff6468bfff8ca2).
  Host and embedded extension both ARM64 and **0.2.0 (48)**, production
  identifiers, no embedded provisioning profile. Host binary SHA256
  f401933b2c94a4a0b35dda213a95101c638d75ac65d35e33dcc376bbd337f677;
  extension binary SHA256
  7ff1c1eb5df7ef5ff119034618bf718459b5a6f0699368324df3fa3241d2c2f9.
  64 localization directories, YandexMobileAds framework present. Checked
  exported native bridge symbols and QA command UI markers absent. This is
  evidence of ordinary artifact isolation, not release or native acceptance.
* Prior physical Debug 0.3.0 (49) upgrade: three existing profile IDs and
  selected UUID preserved; Keychain 3/3 accessible; existing proxy HTTPS
  receipt 3/3 and real PacketTunnel HTTPS egress 2/2. Do not repeat initial
  migration from scratch; check preserved data on final approved candidate.
* Native isolated lab on signed source 2576a82d: prior sixteen
  transport/authentication cases and exact DNS witnesses retained. WG and AWG
  fixed-target healthy and established-loss UDP4/UDP6/DNS matrices now complete:
  36 ordered OFF/active/OFF records in total (18 per protocol). No direct
  fixed-target packets in active runs; no broad no-leak or kill-switch claim.
  See physical acceptance document for exact IDs and independent correlations.
* PRs #381/#382 are ancestors. PRs #377–380 are not ancestors, but their
  relevant source changes were compared by Git object/path against current
  86c4207c. Helper source and corresponding tests are identical; evolved
  provider source retains generation-bound timers and fail-closed engine
  termination (including exit code zero). Backup view evolution adds only
  simulator QA; codec retains legacy format and introduces distinct
  authenticated native envelope with stricter size validation. Physical UDP
  test retains prior case and extends interface/probe coverage. Project
  file adds references without removals. Focused 22 Swift tests and 331
  Python tests +14 subtests passed. Current mirror workflow is byte-identical
  to origin/main. No duplicate cherry-pick, merge, or publication performed.
* Extended native handoff (deferred by owner below): current controlled native
  peer is a LAN address, not reachable over arbitrary cellular WAN. The
  prior interface-bound VPN-OFF TLS evidence is not active native handoff.
  Use an explicitly authorized isolated WAN-reachable UDP peer, validate
  reachability through both underlays and exact synthetic challenge; owner
  must be present to restore Wi-Fi if Mirroring disconnects. Require same
  owned session ID/generation, timed Wi-Fi/cellular/Wi-Fi observations,
  independent external first/after witnesses, no direct escape in a
  complete bounded filtered capture, explicit terminal OFF/rollback.
  Do not expose a router port, deploy a paid server, change the owner VPN
  or use a third-party VPN endpoint without appropriate authorization.

## Fixed exit sequence

1. Finish finite native safety acceptance for **declared** release
   capabilities: fixed-target WG/AWG healthy and fault/escape matrix done;
   functional proxy Wi-Fi/LTE/Wi-Fi smoke PASS; route policy remains.
   Extended instrumented native handoff deferred by explicit owner scope
   decision below; do not claim it passed.
2. Resolve selected dependency source/notice/publication and privacy gates.
   CloudKit remains disabled absent separately approved private entitlement
   and multi-device acceptance. No unverified Smart4 DIRECT or native FIN
   promotion. Do not represent lab transports as production functionality.
3. Integrate only approved and accepted features in a single final production
   candidate. Reconcile outstanding PR patches, preserve mirror fix, set exact
   intended version/build, freeze scope and check release linkage, notices,
   localized metadata and production ad behavior.
4. Signed final candidate: preserve existing profiles/selection/Keychain,
   verify appropriate backup and actual declared transport functionality;
   check exact head CI and signed artifact. Sign/distribute only within
   approved scope. Review release decision and App Store submission separately.

Full original scope remains pending. A narrower safe release would require
an explicit product-owner scope decision; do not silently substitute it.
Current public milestone remains 0.2.0 (48) in project records. No upload,
review or publication is asserted. No production state was changed by this
read-only artifact audit.


## Owner-approved handoff scope adjustment (16 November)

No VPS available; owner approved functional smoke on existing proxy:
active VPN over Wi-Fi, LTE and back, HTTPS reachability and recovery,
restore original Wi-Fi and terminal VPN OFF, preserve profile data.
This is not independent escape testing nor WG/AWG active handoff.
Extended native handoff with controlled WAN UDP peer and filtered
underlay observation is a deferred backlog item, not a PASS. No other
release or publication gate is waived; no server purchase, public port
or account change authorized. Final release must state the tested
capabilities accurately.


### Functional handoff receipt — PASS 16 November 19:55–20:00 MSK

Installed working APL 0.3.0 (49), existing selected proxy, starting
Wi-Fi ON/VPN OFF. Normal connect started the production PacketTunnel
PID 34022. Fresh HTTPS Cloudflare trace in Safari succeeded on Wi-Fi.
With macOS 27 Control Centre mirroring (Command-4), temporarily
disassociated iPhone from its access point, not disabling Wi-Fi radio;
Mirroring and wired CoreDevice continued. Status bar LTE, separate
fresh HTTPS trace succeeded. Rejoined Wi-Fi via Control Centre;
Wi-Fi indicator and a third fresh HTTPS response. All three trace
responses show same external IP, provider PID unchanged throughout,
selected profile unchanged; no manual VPN reconnect. The first LTE
request took several seconds to complete. No raw address retained
in Git. Normal disconnect and Settings verified VPN OFF, no
PacketTunnel process, Wi-Fi restored. No profile edit or installation.
This is the approved functional smoke, not transport-specific native
handoff, continuous socket/zero interruption, or universal leak proof.
Deferred extended native WAN handoff remains in roadmap.

### Exact source review and remaining release identity

The exact physically exercised NativeLab source/notice kit is staged and
verified (409 files; see source delivery draft). No public delivery.
All 26 privacy manifests in isolated unsigned candidate match historical
ordinary bundle byte-for-byte, including the AppMetrica AdSupport tracking
declaration. This is not evidence of actual data transfers or review
compliance. Do not silently change monetization or publish inaccurate
privacy statements. Production native owner and descriptor remain
DEBUG-gated; ordinary unsigned Release does not implement the reviewed
native path. Build a separately staged unsigned production candidate
with explicit final scope, proven no-QA linkage and dependency receipts,
then signed acceptance only with authorization. No automatic promotion.

### Product-only ABI preparation — 16 November

Actual offline arm64 iOS product-only Go archive compiled and C link
probe passed. Archive SHA256 45716d42d434ae6d6576d9a32f47a4ea63d4943f106cb3bb7e6af57c725ea7af;
manifest 1c8f00a729dac97e7670b718d6208d8e67946ea9b2260a9f68eed4a9fa5e0c54.
15 files independently checked. Seven exact bridge C exports (CGoInvoke,
CGoFree, five aplAWGProduct methods), no lab start, CLI or self-test exports.
696 Go packages, only AWG tuntest removed; no module identity or lock drift.
Product-only source selection tests pass. Explicit separate Release-only
Swift driver boundary passes active SDK syntax parse; no ordinary provider
dispatch or project flag change. 337 Python tests +14 subtests PASS.
A full containing Release build was not started: the remote verifier/build
action was blocked by the safety system. Partial shell is private and
incomplete, not a runnable release tool. Do not circumvent this block.
No device, production activation, version bump, signing, distribution or
release. The reviewed bounded runtime (timeouts, path invalidation, scoped
VLESS routes) cannot be promoted wholesale. Production lifecycle, routing,
privacy and final signed acceptance still open.

### Native control lifecycle hardening

Independent source-only fix: the adapter transition timer is disarmed
after readiness, so a suspended health observation previously had no
reply deadline. Each owned native control exchange now has a monotonic
six-second deadline and generation-scoped watchdog, including drain.
A stalled exchange fails closed; superseded and late callbacks cannot
change terminal state. No fallback, inferred drain, OS route or production
activation change. Tests simulate a noncooperative provider reply while
running, and a pending observation superseded by a confirmed stop.
37 focused Swift tests, 337 Python tests and 14 subtests passed.
Full containing Release remains incomplete.

### Launch snapshot and route admission reconciliation

ProfileStore now supplies live routing admission to the existing native
launch boundary. Preparation binds the exact catalog snapshot and legacy
ID set, checks collisions and policy; issuance rechecks before credential
access, before ticket creation and after the write. A stale request
revokes its ticket, retaining cleanup ownership if removal fails.
No new manager, routing action, production activation or ticket purpose.
79 focused default Swift tests, 62 focused Swift with existing explicit
review flags, 337 Python +14 subtests PASS. Not a containing Release build.
