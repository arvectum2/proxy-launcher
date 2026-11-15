# APL iOS 0.3.0 — release acceptance matrix

Snapshot: 15 November 2026; draft PR #383. **Not release authorization**. Published/active source version remains 0.2.0 (48); earlier installed QA version 0.3.0 (49) is not a published release. Physical iPhone is unavailable; do not repeat completed device fixtures or enable unfinished features. Each receipt applies to its exact artifact and scope; a green compile is not runtime evidence.

| Gate | Verified evidence | Status / remaining proof |
|---|---|---|
| Legacy safety and ads | Existing production preflight, Swift/Python regression, unsigned Release; prior supervised legacy storage fingerprints | Local regression accepted; repeat migration/compatibility for final signed artifact; advertising and privacy review |
| Native compiler / profiles | WG/AWG1/VLESS validation; catalog, journal, encrypted backup and synthetic restore | Core accepted; real Keychain and selected profile migration not accepted |
| Native handoff | Metadata-only one-use tickets, concurrent consume, stale revision, provider identity, expiration cleanup and purpose-specific item sizes | Core accepted; actual cross-process Keychain and cleanup invocation not accepted; no automatic cleanup in production |
| Native UI | Simulator-only, ephemeral QA import/export/restore; mixed profile backup tests | Compile/core accepted; actual screen, Files and production UX not accepted |
| Prior native physical fixtures | 20/20 on earlier isolated signed labs: WG/VLESS 10/10, AWG dual-stack valid/fault 8/8, control 2/2 | Accepted only for those scoped artifacts; not evidence of broad WAN/DNS or new source-built Xray |
| Independently built Xray | Pinned source, toolchain and module hashes; local macOS config/lifecycle comparison, iOS static library and unsigned NativeLab link | Build accepted; actual iOS native traffic not accepted; upstream archive not bit-identical |
| AWG | Pinned source, isolated local kernel-bound loopback tests, iOS archive and prior signed fixture | Loopback and earlier scoped device evidence only; real physical underlay, other AWG protocol variants not accepted |
| Network policy | Offline NE settings and route plans, prior separate legacy DNS/QUIC probes | Native full routing, DNS leakage, exclusions, WAN/LAN, MTU and handoff need actual network evidence |
| CloudKit | Fake two-device conflict tests and gated simulator compile, account-bound expiring review | Actual private container opt-in, account switch and two-device acceptance blocked; entitlement off |
| License and provenance | Xray 70, AWG 9, Rust 265 original notice files, 3 MPL source archives; integrity audit | One original notice text missing (tproxy-config); tun original source header preserved separately; final linked closure/SBOM, legal obligations and source delivery unresolved |
| Release controls | Default build has no experimental engine symbols or QA UI; main untouched | Final signed QA, explicit owner-approved scope, signing and submission outstanding |

## Next independent work

- Audit storage and UI lifecycle on synthetic inputs; do not present rehearsal as signed acceptance. Keep bounded metadata cleanup separate from actual device Keychain permissions.
- Finish exact-license-source correspondence and review source-distribution design for final selected artifacts. Unknown license notices remain open rather than inferred.
- Prepare scope-specific device acceptance cases from current receipts, avoiding duplicate hardware work; do not run until authorized and available.
- Treat the previous simulator launch error as unresolved, not a passing test. Only retry with a materially different validated environment.

The canonical checkpoint remains `in_progress`. None of these steps authorizes main merge, signing, real account access, device modification or publication.

Selection authority now includes a persisted nonce bound to each explicit selection; offline A→B→A and legacy selection regression cases pass. Swift359/359, Python415/415 +1527 subtests, unsigned Release and simulator harness typecheck PASS. No runtime acceptance added.

Ordered remaining cases S1/K1/K2/X1/N1/N2/C1/R1 are specified in `APL_IOS_030_REMAINING_ACCEPTANCE_RUNBOOK_2026-11-15.md`. Supplemental Rust evidence is now included in the pinned read-only audit; one missing original license text remains. UI lifecycle is core-tested and compile-checked, not GUI-accepted.
