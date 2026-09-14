# APL-REG-001 — Russian Software Register readiness

## Purpose

Prepare Arvectum Proxy Launcher for inclusion in the Unified Register of Russian Software without confusing repository engineering readiness with external legal or physical evidence.

## Current filing position

- Product/rightsholder: ООО «Арвектум»; private corporate/right-chain proof remains external.
- Primary software class: **02.02 — Программы обслуживания**, subject to final classifier recheck immediately before filing.
- Under the current roadmap, trusted-OS compatibility for this class is planned against **2027-01-01**, subject to a current-law recheck before filing.
- Rospatent registration is useful supporting evidence, not a standalone mandatory gate to the software-register application.
- Registry inclusion is an upstream dependency/candidate prerequisite for the Russia-first NUC code-signing route; it does not itself establish Microsoft public Windows trust.

## Readiness matrix

| Area | Status | Current evidence / next boundary |
|---|---|---|
| Release integrity/provenance | READY | Governed hashes and Russian detached-signature evidence exist for the current release. |
| Rights of ООО «Арвектум» | EXTERNAL | Prove the complete exclusive-right chain for all material product code and assets. |
| Rospatent software registration | OPTIONAL | Use as additional evidence if obtained; do not make it the only proof of rights. |
| Corporate/rightsholder qualification | EXTERNAL | Verify ownership/control and other rightsholder conditions under the current rules. |
| APL-IP-002 | COMPLETE | Governed stack/dependency sovereignty inventory exists; lifecycle remediation handed to APL-REG-001B and release-bound legal work to APL-IP-001. |
| Runtime vendor-cloud independence | READY | No mandatory Arvectum API/cloud, telemetry, license server or updater; upstream proxy is user-supplied configuration. |
| Windows offline build capability | READY | Canonical build supports local hash-locked wheelhouse with `--no-index` and `--require-hashes`. |
| APL-IP-001 automation | PARTIAL | Provenance CI exists; complete human review/legal sign-off and freeze evidence for submitted release. |
| Dependency/license inventory | READY / REFRESH | Governed APL-IP-002 inventory exists; refresh/freeze against exact submitted release. |
| SBOM automation | PARTIAL | CycloneDX SBOM CI exists; retain/freeze SBOM for exact submitted release and complete legal disposition. |
| THIRD_PARTY_NOTICES | PARTIAL | Notice exists and distinguishes runtime/build/OS components; reconcile with exact submitted artifacts/license bundle. |
| IP_PROVENANCE | PARTIAL | Automated source manifest exists; complete human/legal review and clean-IP baseline/tag. |
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
| Two trusted OSes | MISSING / BLOCKER | For class 02.02 plan against 2027-01-01 on current baseline. Select and prove two qualifying OSes under APL-REG-001C. |
| Linux runtime/product support | PARTIAL | Linux/Astra tooling exists, but registry compatibility must be proved on two qualifying OSes. |
| Trusted-OS compatibility protocols | MISSING | Produce repeatable tests and governed evidence for exact submitted release. |
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

### APL-IP-001 — IP provenance & human-authorship hardening

Complete source audit, dependency/license audit, OSS-overlap review, human review of significant modules, remediation where needed, release-bound SBOM, THIRD_PARTY_NOTICES/license bundle, IP_PROVENANCE and clean-IP baseline/tag. Corporate rights documents stay outside public repository.

### APL-REG-001C — trusted Russian OS compatibility

Because 02.02 is the filing class, plan against **2027-01-01** unless law changes before submission.

- choose two qualifying trusted general-purpose OSes from different rightsholders based on official status at execution time;
- implement product/runtime/UI packaging needed for them;
- run clean-host installation/start/stop/routing/no-proxy/restart/uninstall/regression tests;
- record OS edition/version, package hashes and exact product commit/release;
- prepare expert-readable compatibility protocols.

Do not hard-code candidate OS brands in the legal contract until their qualifying status is verified at time of test.

### APL-REG-001D — registry documentation pack

Produce version-frozen Russian documents for product purpose/functionality, system requirements, installation, operation/configuration, removal/recovery, support/maintenance, licensing/price, expert test procedure, known restrictions and external proxy configuration.

### APL-REG-001E — private corporate evidence pack

Keep outside public Git repository: charter/EGRUL materials, ownership/control evidence, author/employee/contractor IP-transfer documents, accounting evidence for applicable foreign payments, applicant powers/authorizations and qualified-signature material. Never commit private keys, УКЭП material, personal data or restricted corporate evidence.

### APL-REG-001F — pre-submission audit

Immediately before filing, re-check current law, classifier, trusted-OS applicability, exact release bytes, rights chain, infrastructure evidence and all registry-facing documents. The filing package must describe reality at submission time, not historical assumptions.

## NUC / Windows trust relationship

Russian Software Register inclusion is an upstream dependency/candidate prerequisite for the Russia-first National Certification Authority code-signing route identified in APL-REL-016. It does not prove Microsoft public Windows trust. APL-REL-016 remains a separate trust/signing workstream and v0.2.5 remains immutable.
