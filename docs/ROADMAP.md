# Arvectum Proxy Launcher — canonical roadmap

Updated: 2026-09-12  
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Canonical branch: `main`  
Current product line: `0.2.4` physically accepted candidate

Status legend: **DONE**, **CURRENT**, **READY**, **IMPLEMENTED**, **PARTIAL**, **HUMAN/LEGAL PENDING**, **ADMIN PENDING**, **STOP-GATE**, **DEFERRED**.

## 0. Repository authority and migration recovery

- **DONE** — source/history/tags were recovered into `arvectum2/proxy-launcher`; `main` is the canonical integration branch.
- **DONE** — current governance, installer/support and repository-identity references are normalized to the new canonical slug without rewriting historical provenance.
- **DONE** — GitVerse mirror logic is owner-independent on the GitHub side because it uses `${{ github.repository }}`; post-migration mirror PASS is recorded for canonical migration SHA `357a1795c07b4a1e0c23ce6cbb553d3bc9feb9fa`.
- **DONE** — exact-SHA GitHub Actions evidence was rebuilt in the new repository for `357a1795c07b4a1e0c23ce6cbb553d3bc9feb9fa`: Windows portable, Windows installer/Gate R6, SAST, SBOM, provenance and Release Evidence Package are green.
- **DONE** — `main` protection restored through active repository ruleset `Protect main`: PR required, required check `build`, strict/up-to-date status policy, conversation resolution, deletion/force-push protection, zero approvals, empty bypass list and `current_user_can_bypass=never`.
- **DONE** — negative merge acceptance test executed on PR #1: immediate merge attempt was rejected with repository rule violation because required status check `build` was queued; PR was closed without merge.
- **MIGRATION CLOSED** — the `arvectum1 → arvectum2` repository migration gate is complete. Production publication remains governed by release-signing and human/legal gates below.

Historical repository identifiers remain valid only inside explicit provenance, closed acceptance, immutable baseline or historical workflow material. They are not current operational authorities.

## 1. Windows product baseline

- **DONE** — customer-proven Windows `0.2.3` system-proxy baseline.
- **DONE** — Windows portable + installer productization, Gate R6 lifecycle, supportability, recovery and DPAPI credential protection.
- **DONE** — APL-WIN-014 exact Inno Setup child-runtime derivation and exact PyInstaller one-file native-runtime trust are sealed into the final candidate evidence.
- **DONE / PHYSICAL PASS** — APL-WIN-014 real-host App Control for Business gate closed on `ARVECTUM-DEMO` for exact candidate commit `e2278dbbd99b0d98ba9e4f836e40b2d60ea94b30`: exact `0.2.3 -> 0.2.4` upgrade, runtime/PAC/WinINET, rollback, repair and uninstall all PASS; App Control before/after PASS; Arvectum Code Integrity event `3077` count `0`. Canonical closure record: `docs/evidence/APL_WIN_014_FINAL_PHYSICAL_ACCEPTANCE_2026-09-11.md`.
- **PARTIAL / IMPLEMENTED / OWNER EVIDENCE EXPORT READY** — APL-REL-014 repository gate is implemented: an exact `0.2.4` identity contract, lifecycle/recovery evidence binder and mandatory REL-013 signed-asset binding now prevent release publication if the signed Setup/portable set differs from the APL-WIN-014-proven bytes. The preserved raw `candidate_evidence.json` and physical result still must be exported/materialized into the final release set before REL-011; APL-WIN-014 alone does not close the signed-set ceremony.

The accepted `0.2.4` physical candidate is immutable at source commit `e2278dbbd99b0d98ba9e4f836e40b2d60ea94b30`. Documentation-only closure commits do not change its accepted product identity.

## 2. Russian-first release trust

- **DONE** — APL-REL-010 real Rutoken/CryptoPro POC: detached signing and verification PASS.
- **DONE** — current company УКЭП classified `RELEASE-EVIDENCE-ONLY`; Code Signing EKU is absent.
- **DONE** — APL-REL-011 owner-operated signed-release manifest integration.
- **DONE** — APL-REL-012 end-user verification UX.
- **DONE** — APL-REL-013 fail-closed Russian production release gate.
- **PARTIAL / IMPLEMENTED / OWNER MATERIALIZATION REQUIRED** — APL-REL-014 exact signed-set lifecycle/recovery gate is repository-complete for the selected `0.2.4` candidate. The remaining per-release operation is to export the preserved raw candidate/physical evidence, generate canonical `apl-rel-014-lifecycle-evidence.json` inside the final release directory, let REL-011 sign it as a normal asset, and obtain REL-013 `rel014_signed_asset_binding = PASS`.
- **NOT ACTIVATED** — embedded Russian code signing / ОТУЦ production identity remains a separate future gate.

The historical `v0.2.3` tag is immutable and must not be moved. The physically accepted `0.2.4` candidate is not automatically a public stable release: public tagging/publication still requires the applicable release and human/legal gates.

## 3. IP / legal / sovereignty

- **DONE** — APL-IP-002 platform sovereignty audits.
- **DONE** — APL-IP-003 canonical source refactor, Slices 1–23.
- **DONE** — APL-IP-004 promoted-artifact third-party license bundle engineering.
- **[Web] DONE — post-APL-IP-004 review reconciliation** for immutable candidate `ef9846e151a2e4e7046169e0787603969018cc97`.
- **CONDITIONAL / POST-APL-IP-004 ENGINEERING RECONCILED / HUMAN-LEGAL PENDING** — historical technical reconciliation remains valid evidence, but it is not legal approval and has been superseded for final candidate binding by the later post-#172 reconciliation.
- **HUMAN/LEGAL PENDING** — R-1 author → ООО rights basis, R-2 actual Rospatent status, R-3 corporate/interested-transaction basis, factual confirmation and explicit final APL-IP-001 decision.
- **[Web after explicit APPROVED] — create governed clean-IP baseline/tag** only for the exact candidate authorized by the completed human/legal sign-off.
- **RULE** — repository migration or documentation closure changes the canonical repository state, not the immutable accepted product candidate. Any later material product/build/package change requires a new exact reconciliation before clean-IP approval and cannot inherit the APL-WIN-014 physical PASS automatically.
- **HOLD** — AppImage remains outside promoted commercial scope until its downstream/type-2-runtime obligations are separately cleared.

## 4. Linux / Astra Linux

- **DONE** — APL-LNX-001..009 engineering, diagnostics, Debian `.deb`, AppImage engineering and Ubuntu CI acceptance.
- **READY AFTER REMAINING RELEASE/PRESERVATION WORK** — convert `ARVECTUM-DEMO` to persistent Windows 11 + Astra Linux SE 1.8 dual boot only after the APL-WIN-014 accepted candidate/policy/evidence are safely preserved and any remaining Windows release evidence that requires this host is exported.
- **READY** — APL-LNX-010 real Astra acceptance.
- **PENDING** — Gate R8 closes only from real Astra-host evidence.
- Preferred promoted Linux/Astra lane remains Debian `.deb`; AppImage remains on HOLD for promoted commercial use.

## 5. macOS

- **DONE** — APL-MAC-001..008 engineering/acceptance track and Gate R9 evidence retained.
- **DEFERRED** — Apple production identity signing/notarization and controlled endpoint-denied build-input hardening under the Russia-first priority model.

## 6. Per-application routing

- **DONE** — APL-ROUTE-001 platform-neutral rule model.
- **DONE** — APL-ROUTE-002 feasibility matrix.
- **AUTONOMOUS COMPLETE / LOCAL-NATIVE PENDING** — APL-ROUTE-003 control-plane prototype.
- **DONE** — APL-ROUTE-004 durable ownership/recovery/security journal.
- **STOP-GATE** — before Windows native production enforcement, deliberately choose an accepted enforcement architecture; test-signing/developer modes are not a production workaround.

Per-application routing is a product-next-stage item after the current Windows release baseline is trustworthy; it should not be mixed into release closure.

## 7. Immediate execution order

1. **[Web/GitHub] DONE** — `arvectum2` repository reconciliation closed on migration baseline `357a1795c07b4a1e0c23ce6cbb553d3bc9feb9fa` with green exact-SHA CI/evidence and GitVerse mirror.
2. **[Admin] DONE** — `main` protection restored and negative merge acceptance test PASS on PR #1.
3. **[Win] DONE** — APL-WIN-014 real App Control cross-version physical gate PASS on `ARVECTUM-DEMO` for candidate `e2278dbbd99b0d98ba9e4f836e40b2d60ea94b30`; preserve candidate, R2 policy and physical evidence, and do not remove the accepted supplemental policy until deliberate cleanup.
4. **[Release] CURRENT / IMPLEMENTED / OWNER MATERIALIZATION REQUIRED** — export/hash-bind the preserved raw `candidate_evidence.json` and authoritative APL-WIN-014 physical result, run `apl_rel_014_exact_evidence.py` into the exact `0.2.4` final release directory, and require the resulting `apl-rel-014-lifecycle-evidence.json` to become a normal REL-011 signed asset.
5. **[Human] PARALLEL** — close R-1/R-2/R-3 and final APL-IP-001 authorized decision.
6. **[Release] AFTER 4–5 AS APPLICABLE** — run the governed REL-011/012/013 owner-operated ceremony for the exact approved set; REL-013 must report both `rel014_exact_lifecycle_evidence = PASS` and `rel014_signed_asset_binding = PASS`; create a new immutable SemVer tag only when authorized, and publish only that exact verified set.
7. **[Linux] NEXT PLATFORM** — after Windows evidence preservation is complete, install Astra dual boot, execute APL-LNX-010 and close Gate R8.
8. **[Product] THEN** — resolve APL-ROUTE-003 Windows enforcement STOP-GATE and begin the next per-application-routing increment.

## Completion discipline

Do not substitute migrated history for new-repository CI evidence, CI for physical App Control/Astra evidence, or automation for human/legal decisions. Do not rewrite historical repository identities where they are part of provenance. Do not retarget immutable tags. Do not treat a documentation-only commit as a different accepted product candidate. Current operational references must resolve to `arvectum2/proxy-launcher`.
