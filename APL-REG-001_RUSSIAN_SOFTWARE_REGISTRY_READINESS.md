# APL-REG-001 — Russian Software Register readiness

## Purpose

Prepare Arvectum Proxy Launcher for inclusion in the Unified Register of Russian Software without confusing repository engineering readiness with external legal or physical evidence.

## Current filing position

- Product/rightsholder: ООО «Арвектум»; private corporate/right-chain proof remains external.
- Primary software class: **02.02 — Программы обслуживания**, subject to final classifier recheck immediately before filing.
- Under the current roadmap, trusted-OS compatibility for this class is planned against **2027-01-01**, subject to a current-law recheck before filing.
- Rospatent registration is useful supporting evidence, not a standalone mandatory gate to the software-register application.
- Registry inclusion is an upstream dependency/candidate prerequisite for the Russia-first NUC code-signing route; it does not itself establish Microsoft public Windows trust.
- **Execution hold (2026-09-14): APL-REG-001C is paused until real acceptance has been completed on two target Russian OSes. The planned acceptance pair is Astra Linux Special Edition + РЕД ОС, subject to re-verification of qualifying trusted-software status and different-rightsholder status at the time of test. Do not resume registry engineering/documentation work past this gate until both real-host acceptance runs exist.**

## Readiness matrix

| Area | Status | Current evidence / next boundary |
|---|---|---|
| Release integrity/provenance | READY | Governed hashes and Russian detached-signature evidence exist for the current release. |
| Rights of ООО «Арвектум» | EXTERNAL / BLOCKER | Verify/execute the complete exclusive-right chain for the exact submitted object; APL-IP-001 R-1 remains human/legal. |
| Rospatent software registration | OPTIONAL / VERIFY IF USED | Use as additional evidence if obtained; APL-IP-001 R-2 requires factual verification if cited. |
| Corporate/rightsholder qualification | EXTERNAL / BLOCKER | Verify ownership/control and applicable corporate basis; APL-IP-001 R-3 remains human/legal. |
| APL-IP-002 | COMPLETE | Governed stack/dependency sovereignty inventory exists; lifecycle remediation handed to APL-REG-001B and release-bound legal work to APL-IP-001. |
| Runtime vendor-cloud independence | READY | No mandatory Arvectum API/cloud, telemetry, license server or updater; upstream proxy is user-supplied configuration. |
| Windows offline build capability | READY | Canonical build supports local hash-locked wheelhouse with `--no-index` and `--require-hashes`. |
| APL-IP-001 engineering reconciliation | READY / HUMAN-LEGAL GATE | Exact v0.2.5 source/tag/artifact identity, provenance and SBOM evidence are governed; R-1..R-4 remain real human/legal gates and no clean-IP tag is authorized. |
| Human authorship/control carry-forward | EXTERNAL / BLOCKER | Historical factual provenance exists; authorized human must carry it forward to exact v0.2.5 drift and release scope under R-4. |
| Dependency/license inventory | READY / REFRESH | Governed APL-IP-002 inventory exists; refresh/freeze against exact submitted release. |
| SBOM automation | READY / RELEASE FREEZE | Exact accepted v0.2.5 source has successful CycloneDX evidence; preserve/freeze exact SBOM bytes for submitted release and legal disposition. |
| THIRD_PARTY_NOTICES | PARTIAL / RELEASE FREEZE | Notice exists and distinguishes runtime/build/OS components; reconcile with exact submitted artifacts/license bundle. |
| IP_PROVENANCE | READY / HUMAN-LEGAL GATE | Exact accepted v0.2.5 source is bound to successful provenance evidence; ownership/authorship conclusions remain human/legal. |
| Clean-IP baseline/tag | BLOCKED | Must not be created until APL-IP-001 R-1..R-4 are genuinely completed and canonical sign-off is explicitly approved. |
| Foreign payment/dependency evidence | EXTERNAL | Accounting/legal review of applicable foreign payments, licenses, services and rights remains outside public repo. |
| APL-REG-001B lifecycle contract/tooling | READY / PHYSICAL GATE | Contract, fail-closed release evidence generator and CI exist. Physical Russian perimeter evidence is still required. |
| Source/object-code storage infrastructure | PHYSICAL BLOCKER | Target is Russian-controlled authoritative source/artifact storage. GitVerse is a candidate; current mirror existence alone is not proof. |
| Build/compilation infrastructure | TOOLING READY / PHYSICAL BLOCKER | Offline hash-locked build and controlled build-input archive exist; execute exact release on a Russian-controlled production build host and retain evidence. |
| Release/distribution infrastructure | PHYSICAL BLOCKER | GitHub Releases may be secondary only. Establish and evidence Russian-controlled primary artifact/distribution location. |
| Activation/license-key infrastructure | N/A CURRENT VERSION | No activation, subscription control plane or license-key server exists. Reopen if product scope changes. |
| GitVerse | CANDIDATE / EVIDENCE REQUIRED | Russian mirror/candidate lifecycle component; verify operator/hosting/control and promote deliberately, not by assumption. |
| Russian-language GUI | PARTIAL | Verify exact submitted version and remove mandatory untranslated UI where present. |
| Functional characteristics document | PARTIAL | Convert existing technical documentation into expert-facing registry documentation. |
| Install/operation/uninstall manual | PARTIAL | Existing material is substantial but needs a frozen registry-facing manual for submitted version. |
| Support/maintenance statement | MISSING | Document support, warranty/maintenance and source modification by an eligible Russian entity/person. |
| Price/licensing statement | MISSING | State price or price-determination procedure, or lawful free/open licensing terms, as applicable. |
| Expert test package | MISSING | Prepare clean test copy plus deterministic installation and verification instructions. |
| Software class | READY / RECHECK | 02.02 — Программы обслуживания; recheck classifier and actual release immediately before filing. |
| Two trusted OSes | WAITING ON REAL-HOST ACCEPTANCE / BLOCKER | Planned pair: Astra Linux Special Edition + РЕД ОС. Resume APL-REG-001C only after both real-host acceptance runs are completed and their qualifying status is rechecked at execution time. |
| Linux runtime/product support | PARTIAL / PAUSED | Existing Linux/Astra tooling may be reused. No further registry-compatibility implementation is scheduled until the two-OS acceptance gate is executed. |
| Trusted-OS compatibility protocols | WAITING ON ACCEPTANCE | Build governed protocols from actual Astra Linux SE and РЕД ОС acceptance evidence; do not substitute generic Linux CI for physical acceptance. |
| Electronic application and УКЭП | EXTERNAL | Submit through operator's current electronic process using an authorized qualified signature. |

## Work order

### APL-REG-001A — classifier decision — DECIDED

Repository decision: `APL-REG-001A_SOFTWARE_CLASSIFICATION_DECISION.md`.

Current filing position: primary class 02.02; no additional classes for current scope; trusted-OS compatibility date 2027-01-01 under current baseline; mandatory final recheck before filing.

### APL-IP-002 — Russian stack & dependency sovereignty audit — COMPLETE

Repository evidence:

- `APL-IP-002_RUSSIAN_STACK_DEPENDENCY_SOVEREIGNTY_AUDIT.md`;
- `compliance/APL_IP_002_STACK_SOVEREIGNTY.json`;
- `tests/test_apl_ip_002_sovereignty_contract.py`;
- `.github/workflows/apl-ip-002-sovereignty.yml`.

Key result: current application runtime has no mandatory vendor-cloud control plane; the main sovereignty gap is the surrounding source/build/release lifecycle. Production Windows build can operate from a local hash-locked wheelhouse without PyPI.

### APL-REG-001B — sovereign lifecycle evidence — REPOSITORY TOOLING COMPLETE / PHYSICAL GATE OPEN

Repository evidence:

- `APL-REG-001B_SOVEREIGN_LIFECYCLE.md`;
- `compliance/APL_REG_001B_SOVEREIGN_LIFECYCLE.json`;
- `tools/apl_reg_001b_release_evidence.py`;
- `tests/test_apl_reg_001b_sovereign_lifecycle.py`;
- `.github/workflows/apl-reg-001b-sovereign-lifecycle.yml`.

Target chain:

`Russian authoritative source → Russian-controlled build host → offline governed inputs → exact artifacts → Russian authoritative artifact/distribution storage → release evidence bundle`.

GitHub/GitHub Actions/GitHub Releases can remain development/public secondary channels but are not the filing-grade sovereign baseline. Existing `tools/archive_windows_build_inputs.ps1` plus `tools/clean_build_windows.ps1 -WheelhousePath` already provide the controlled/offline Windows build primitives.

The release evidence generator fails closed unless the exact build records `dependency_mode=offline-hash-locked`, a concrete source commit and matching artifact SHA-256. It does not claim physical Russian infrastructure is proven. Before filing, perform and retain the physical source/build/artifact/distribution evidence described in the APL-REG-001B contract.

### APL-IP-001 — IP provenance & human-authorship hardening — ENGINEERING RECONCILED / HUMAN-LEGAL GATE OPEN

Current canonical repository evidence:

- `compliance/APL_IP_001_V0_2_5_CLEAN_IP.json`;
- `docs/evidence/APL_IP_001_V0_2_5_CANDIDATE_RECONCILIATION_2026-09-14.md`;
- `docs/APL_IP_001_V0_2_5_SIGNOFF.md`;
- `docs/legal/APL_IP_001_RIGHTS_ASSIGNMENT_V0_2_5_CANDIDATE_ADDENDUM_2026-09-14.md`;
- `IP_PROVENANCE.md`;
- `tests/test_apl_ip_001_v0_2_5_reconciliation.py`;
- `.github/workflows/apl-ip-001-v0-2-5.yml`.

Exact accepted v0.2.5 object is now governed by source commit/tree, immutable tag identity and accepted application/Setup SHA-256. The exact accepted source has successful APL-IP-001 provenance and CycloneDX SBOM workflow evidence. Material runtime drift since the historical 0.2.3 sign-off was bounded and engineering-reviewed; the old 0.2.3 sign-off is no longer treated as the current release approval object.

Repository automation remains deliberately fail-closed. It cannot prove authorship/ownership or create a clean-IP tag. Before filing, complete the actual human/legal findings:

- R-1 — executed rights basis covering the exact object;
- R-2 — factual Rospatent status if relied upon;
- R-3 — applicable corporate approval/exception basis;
- R-4 — authorized human factual authorship/control carry-forward to v0.2.5 and selected release scope.

AppImage remains outside the current clean-IP approval scope on HOLD. The immutable `v0.2.5` tag must not be moved.

### APL-REG-001C — trusted Russian OS compatibility — PAUSED / WAITING ON TWO REAL-HOST ACCEPTANCE RUNS

Because 02.02 is the filing class, plan against **2027-01-01** unless law changes before submission.

Working acceptance pair:

- **Astra Linux Special Edition**;
- **РЕД ОС**.

This pair is an execution target, not a frozen legal assertion. Immediately before each acceptance run, re-verify that the tested editions qualify for the applicable trusted-software requirement and that the two products satisfy the different-rightsholder requirement then in force.

**Resume gate:** do not continue APL-REG-001C implementation, registry compatibility claims, or APL-REG-001D/F work that depends on compatibility until real acceptance has been completed on both OSes.

Each acceptance run must retain enough evidence to identify reality, including at minimum:

- OS product, edition and exact version/build;
- OS/rightsholder qualification check current at test time;
- exact Proxy Launcher commit/release and package SHA-256;
- clean installation result;
- application start/stop;
- proxy routing and no-proxy behavior;
- restart/recovery/autostart behavior where included in the tested product scope;
- diagnostics/log collection sufficient to investigate failures;
- uninstall/removal and post-state;
- dated human acceptance result and supporting machine-readable/raw evidence where practical.

After both acceptance runs exist, resume from this exact point: reconcile failures/differences, implement only the required compatibility changes, rerun affected acceptance cases, freeze the resulting compatibility contract, and produce expert-readable protocols for the submitted release.

Generic Ubuntu/GitHub CI, container tests or claimed Python portability are not substitutes for these two real-host acceptance runs.

### APL-REG-001D — registry documentation pack

Produce version-frozen Russian documents for product purpose/functionality, system requirements, installation, operation/configuration, removal/recovery, support/maintenance, licensing/price, expert test procedure, known restrictions and external proxy configuration.

### APL-REG-001E — private corporate evidence pack

Keep outside public Git repository: charter/EGRUL materials, ownership/control evidence, author/employee/contractor IP-transfer documents, accounting evidence for applicable foreign payments, applicant powers/authorizations and qualified-signature material. Never commit private keys, УКЭП material, personal data or restricted corporate evidence.

### APL-REG-001F — pre-submission audit

Immediately before filing, re-check current law, classifier, trusted-OS applicability, exact release bytes, rights chain, infrastructure evidence and all registry-facing documents. The filing package must describe reality at submission time, not historical assumptions.

## NUC / Windows trust relationship

Russian Software Register inclusion is an upstream dependency/candidate prerequisite for the Russia-first National Certification Authority code-signing route identified in APL-REL-016. It does not prove Microsoft public Windows trust. APL-REL-016 remains a separate trust/signing workstream and v0.2.5 remains immutable.
