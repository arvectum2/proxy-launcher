# Arvectum Proxy Launcher — canonical roadmap

Updated: 2026-09-10  
Canonical GitHub repository: `arvectum2/proxy-launcher`  
Canonical branch: `main`  
Current product line: `0.2.3`

Status legend: **DONE**, **CURRENT**, **READY**, **PARTIAL**, **HUMAN/LEGAL PENDING**, **ADMIN PENDING**, **STOP-GATE**, **DEFERRED**.

## 0. Repository authority and migration recovery

- **DONE** — source/history/tags were recovered into `arvectum2/proxy-launcher`; `main` is the canonical integration branch.
- **DONE** — current governance, installer/support and repository-identity references are normalized to the new canonical slug without rewriting historical provenance.
- **DONE** — GitVerse mirror logic is owner-independent on the GitHub side because it uses `${{ github.repository }}`; post-migration mirror PASS is recorded for canonical migration SHA `357a1795c07b4a1e0c23ce6cbb553d3bc9feb9fa`.
- **DONE** — exact-SHA GitHub Actions evidence was rebuilt in the new repository for `357a1795c07b4a1e0c23ce6cbb553d3bc9feb9fa`: Windows portable, Windows installer/Gate R6, SAST, SBOM, provenance and Release Evidence Package are green.
- **DONE** — `main` protection restored through active repository ruleset `Protect main`: PR required, required check `build`, strict/up-to-date status policy, conversation resolution, deletion/force-push protection, zero approvals, empty bypass list and `current_user_can_bypass=never`.
- **DONE** — negative merge acceptance test executed on PR #1: immediate merge attempt was rejected with repository rule violation because required status check `build` was queued; PR was closed without merge.
- **MIGRATION CLOSED** — the `arvectum1 → arvectum2` repository migration gate is complete. Production publication remains governed by the remaining Windows physical-host, release-signing and human/legal gates below.

Historical repository identifiers remain valid only inside explicit provenance, closed acceptance, immutable baseline or historical workflow material. They are not current operational authorities.

## 1. Windows product baseline

- **DONE** — customer-proven Windows `0.2.3` system-proxy baseline.
- **DONE** — Windows portable + installer productization, Gate R6 lifecycle, supportability, recovery and DPAPI credential protection.
- **DONE** — sealed APL-WIN-014 Inno Setup 6.7.1 runtime derivation/evidence engineering is retained in history.
- **CURRENT / LOCAL** — finish the real-host APL-WIN-014 App Control for Business gate on ARVECTUM-DEMO using the exact retained `0.2.2 P0.4` predecessor and current `0.2.3` artifacts. Same-version repair is not cross-version evidence.
- **PARTIAL / READY** — APL-REL-014 exact signed-set lifecycle/recovery evidence remains to be closed if not already exported from the physical stand.

The sealed `0.2.3` product baseline is not silently mutated by repository migration work.

## 2. Russian-first release trust

- **DONE** — APL-REL-010 real Rutoken/CryptoPro POC: detached signing and verification PASS.
- **DONE** — current company УКЭП classified `RELEASE-EVIDENCE-ONLY`; Code Signing EKU is absent.
- **DONE** — APL-REL-011 owner-operated signed-release manifest integration.
- **DONE** — APL-REL-012 end-user verification UX.
- **DONE** — APL-REL-013 fail-closed Russian production release gate.
- **NOT ACTIVATED** — embedded Russian code signing / ОТУЦ production identity remains a separate future gate.

The historical `v0.2.3` tag is immutable and must not be moved to the migrated/current tree. Because the current tree has changed after that tag, any new stable public release must use a new SemVer version/tag. If scope remains migration/release hardening only, `0.2.4` is the natural patch candidate; do not bump until the exact release candidate is selected.

## 3. IP / legal / sovereignty

- **DONE** — APL-IP-002 platform sovereignty audits.
- **DONE** — APL-IP-003 canonical source refactor, Slices 1–23.
- **DONE** — APL-IP-004 promoted-artifact third-party license bundle engineering.
- **[Web] DONE — post-APL-IP-004 review reconciliation** for immutable candidate `ef9846e151a2e4e7046169e0787603969018cc97`.
- **CONDITIONAL / POST-APL-IP-004 ENGINEERING RECONCILED / HUMAN-LEGAL PENDING** — historical technical reconciliation remains valid evidence, but it is not legal approval and has been superseded for final candidate binding by the later post-#172 reconciliation.
- **HUMAN/LEGAL PENDING** — R-1 author → ООО rights basis, R-2 actual Rospatent status, R-3 corporate/interested-transaction basis, factual confirmation and explicit final APL-IP-001 decision.
- **[Web after explicit APPROVED] — create governed clean-IP baseline/tag** only for the exact candidate authorized by the completed human/legal sign-off.
- **RULE** — repository migration changes the canonical repository location, not the immutable candidate commit/tree or historical evidence. Any later material product/build/package change requires a new exact reconciliation before clean-IP approval.
- **HOLD** — AppImage remains outside promoted commercial scope until its downstream/type-2-runtime obligations are separately cleared.

## 4. Linux / Astra Linux

- **DONE** — APL-LNX-001..009 engineering, diagnostics, Debian `.deb`, AppImage engineering and Ubuntu CI acceptance.
- **READY AFTER WINDOWS-ONLY GATES** — convert ARVECTUM-DEMO to persistent Windows 11 + Astra Linux SE 1.8 dual boot while preserving Windows recovery/EFI state.
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

Per-application routing is a product-next-stage item after the current Windows release/repository baseline is trustworthy; it should not be mixed into migration recovery.

## 7. Immediate execution order

1. **[Web/GitHub] DONE** — `arvectum2` repository reconciliation closed on migration baseline `357a1795c07b4a1e0c23ce6cbb553d3bc9feb9fa` with green exact-SHA CI/evidence and GitVerse mirror.
2. **[Admin] DONE** — `main` protection restored and negative merge acceptance test PASS on PR #1.
3. **[Win] CURRENT** — close APL-WIN-014 real App Control cross-version gate and remaining APL-REL-014 evidence on ARVECTUM-DEMO; export/hash-verify evidence.
4. **[Human] PARALLEL** — close R-1/R-2/R-3 and final APL-IP-001 authorized decision.
5. **[Release] AFTER 3–4 AS APPLICABLE** — select the next immutable SemVer candidate, rebuild exact-SHA release evidence in `arvectum2`, run REL-011/012/013 owner-operated ceremony, then publish only the exact verified set.
6. **[Linux] NEXT PLATFORM** — install Astra dual boot, execute APL-LNX-010 and close Gate R8.
7. **[Product] THEN** — resolve APL-ROUTE-003 Windows enforcement STOP-GATE and begin the next per-application-routing increment.

## Completion discipline

Do not substitute migrated history for new-repository CI evidence, CI for physical App Control/Astra evidence, or automation for human/legal decisions. Do not rewrite historical repository identities where they are part of provenance. Do not retarget immutable tags. Current operational references must resolve to `arvectum2/proxy-launcher`.
