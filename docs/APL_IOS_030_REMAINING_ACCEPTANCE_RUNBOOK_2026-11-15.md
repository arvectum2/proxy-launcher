# Remaining acceptance runbook — APL iOS 0.3.0

Status: prepared, **not executed**, not permission to sign, install, change system settings, export owner records, or submit. Source branch PR #383. Previous isolated physical20/20 receipts remain valid only for their earlier exact artifacts. Do not repeat them unless a new artifact or affected behavior requires it. Device is unavailable as of this checkpoint.

## Preparation and stop gates

1. Record exact source HEAD, build inputs, unsigned artifact hashes, protocol scope and test receipts. Require clean checkout and matching CI; current production baseline is 0.2.0 (48), not published 0.3.0.
2. Verify the default Release has no research-engine or QA UI activation, production ads pass preflight, no new entitlements. Inventory all actual selected binary dependencies and complete legal/source-delivery review before promotion.
3. When the owner makes a device available, obtain explicit authorization for exact artifact, test identity, changes and rollback. Do not infer approval from old lab permission. Confirm exclusive access, unlocked state, current VPN status and baseline profile/selection/organization fingerprints without exposing secrets. If unavailable or inconsistent, stop rather than partially modifying the device.
4. A signed test must identify its exact app and extension digests and test data namespace. Preserve existing VPN and credentials. A failure, unexpected manager, account or state, or incomplete cleanup is a blocker, not a PASS.

## Ordered cases and required receipts

| ID | Scope | Pass condition | Failure / recovery |
|---|---|---|---|
| S1 | Disposable simulator, native backup QA view | Synthetic WG/AWG/VLESS import, count-only preview, cancel and wrong password; encrypted Files export/restore; no data visible after background or dismissal; stale callback cannot add a record | Clear temporary session, remove only owned disposable artifacts; no owner Keychain operations |
| K1 | Existing isolated signed lab, synthetic shared Keychain | Separate sender/provider processes; exact selection nonce, revision and session receipt; one successful consume; replay/wrong nonce rejected; no credential bytes in control message | Revoke exact lab ticket; clean exact lab keys only after confirmed stop; no sweeping owner records |
| K2 | Same isolated namespace, storage recovery | Expired metadata cleanup only, live ticket retained; interrupted journal restores exact baseline, fresh IDs and selection preserved | Stop mutation on unknown journal, malformed entry or unavailable store; preserve existing items |
| X1 | New source-built Xray artifact, isolated signed lab | Exact new library digest and signed host/NE identity; run only materially new source-built synthetic data-plane cases within previously accepted protocol capability scope; independent nonce witness and lifecycle cleanup | Stop exact owned test session on failure, verify owner baseline; no broad production claim |
| N1 | Later native provider network-policy candidate | Independently witnessed expected underlay and route/DNS results for explicitly declared supported capabilities; distinguish LAN/off-link and IPv4/IPv6; failure closes rather than routes unexpectedly | Stop and restore, record denial/timeout as failure where positive control is required; no claim from route-plan compile alone |
| N2 | Explicitly approved network handoff | Wi-Fi to LTE and back during active owned test session; exact session generation, independent receipts and teardown; no unintended fallback or owner mutation | Abort if baseline cannot be restored; do not toggle radios without separate authorization |
| C1 | Explicit private CloudKit opt-in, two test instances | Account change/absence, changed server version, conflict and expired review reject; manual exclusion-only payload, no proxy credentials | Do not change real account or delete existing cloud data; retain previous local state; actual container entitlement/approval prerequisite |
| R1 | Final signed product candidate | Existing profile/selection/organization and legacy backup intact; allowed features alone exposed, ads/localization/privacy confirmed; test results linked to exact signed artifact | Revert owned changes; no submission if any mandatory gate is open |

S1 is simulator-only and may be completed independently if the simulator launch service becomes usable. K1/K2 are isolated signed acceptance, not production. X1 requires the exact source-built artifact; the older upstream physical20 receipts cannot be substituted. N1/N2, C1 and R1 require their own explicitly approved scope and prerequisites. No step enables a feature solely because an earlier step passed.

## Receipt format

Record case ID, timestamp, exact source commit, artifact and inputs SHA-256, environment and scoped capability, expected/actual nonsecret counters, independent positive and negative controls, cleanup/baseline result, result PASS/FAIL/BLOCKED, and unresolved limitations. Never collect or store raw keys, passwords, full user profile data, cloud account ID, or network payload in these receipts. A skipped or unavailable prerequisite is BLOCKED, not PASS. The canonical checkpoint remains in_progress until the actual Definition of Done is satisfied.

## Scope override — 25 November 2026

Owner closes extended physical WAN/handoff for this release: N2 and the extended WAN/handoff portion of N1 are deferred, NOT TESTED, not mandatory current-scope blockers. Reopen on relevant user complaints or controlled WAN infrastructure becoming available. All other N1 and release requirements remain applicable. See APL_IOS_030_WAN_HANDOFF_QA_2026-11-25.md.
