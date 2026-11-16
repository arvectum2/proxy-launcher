# APL iOS 0.3.0 — release exit gate (16 November 2026)

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
* Active handoff remains a real prerequisite: current controlled native
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
   reachable independent endpoint for actual Wi-Fi/LTE and route policy
   remain, without repeating verified cases.
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
