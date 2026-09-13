# APL-REG-001 — Russian Software Registry readiness

Status: **PRE-SUBMISSION WORKSTREAM OPEN**  
Audit date: **2026-09-13**  
Baseline: `main` @ `c6a93e096eedde7be23ade93cd7372a04db311a0`  
Tracking issue: #46

## 1. Goal and boundary

Prepare Arvectum Proxy Launcher and the ООО «Арвектум» evidence package for an application to the Unified Register of Russian Programs for Computers and Databases under the rules established by Government Resolution No. 1236 in the edition effective on the audit date.

Repository changes can make the product **application-ready**. Inclusion in the register itself is an external decision of the competent authority/expert process and is not a repository acceptance criterion.

## 2. Regulatory baseline

The pre-submission review must use the law actually effective on the submission date. The baseline for this document is:

- Government Resolution of the Russian Federation No. 1236 of 2015-11-16, edition including amendments effective through 2026-09-13;
- Government Resolution No. 1937 of 2025-11-28, effective from 2026-03-01, including staged trusted-OS compatibility requirements;
- Government Resolution No. 1007 of 2026-08-13, whose relevant amendments to the register rules are effective from 2026-09-01;
- the software classifier approved by Ministry of Digital Development Order No. 486, in the edition effective on the actual submission date.

### 2.1 Rospatent is evidence, not a gate

A Rospatent software-registration certificate can strengthen the evidence package, but APL-REG-001 does not treat Rospatent registration as a mandatory prerequisite to a registry application. The controlling gate is evidence that the exclusive right and the rightsholder satisfy the applicable requirements of Resolution No. 1236.

### 2.2 Trusted-OS compatibility changes the delivery plan

Resolution No. 1937 introduced a requirement for affected software to be compatible with at least two operating systems meeting the statutory trusted-software requirements, subject to the exceptions in the rules. The requirement is staged by software category.

APL-REG-001A has classified the current Proxy Launcher product scope as **02.02 — Программы обслуживания**. On the regulatory baseline current at 2026-09-13, the two-trusted-OS requirement for class 02.02 applies from **2027-01-01**.

That date is therefore a concrete delivery deadline rather than an unresolved classification-dependent estimate. The classification and law must still be rechecked immediately before filing.

## 3. Product classification decision

Current public product description: Arvectum Proxy Launcher is a local user-space client/utility that routes traffic through a configured upstream HTTP proxy while exposing local HTTP, SOCKS5 and PAC endpoints; `no_proxy` rules can route selected destinations directly.

**APL-REG-001A decision:**

- primary class: **02.02 — Программы обслуживания**;
- additional classes: **none for the current `0.2.x` product scope**;
- decision record: `APL-REG-001A_SOFTWARE_CLASSIFICATION_DECISION.md`;
- tracking issue: #48.

Rejected for the current scope:

- **02.13 — Сетевая операционная система**: Proxy Launcher is not an OS, router firmware or full software-router/network-OS layer; registry examples in 02.13 include vESR and router software «Факел»;
- **02.06 — Серверное и связующее ПО**: local HTTP/SOCKS5/PAC listeners are supporting mechanisms of the desktop utility, not a standalone middleware/server platform;
- **02.08 — Средства мониторинга и управления**: monitoring/managing an estate of external objects is not the principal product function;
- **03.* — Средства обеспечения информационной безопасности**: the product does not implement or claim cryptographic VPN protection, NGFW/firewall, IDS/IPS, DLP, access-control or another independent protection function;
- **05.* — Прикладное ПО**: the product solves an auxiliary system/network-access task rather than a domain/business subject-matter task.

Reclassification is mandatory if future releases materially add packet-level/system routing, router/appliance mode, an independent server/middleware role, security-policy/protection functions, VPN/cryptography or another function mapped to a different classifier class.

## 4. Readiness audit

Status vocabulary:

- `READY` — evidence already exists and is usable with normal version refresh;
- `PARTIAL` — useful implementation/evidence exists but registry-specific evidence is incomplete;
- `MISSING` — required work or evidence has not been established;
- `EXTERNAL` — corporate, physical, regulatory or submission action outside the public repository;
- `OPTIONAL` — useful supporting evidence, not treated as a standalone legal gate.

| Area | Status | Finding / required action |
|---|---|---|
| Windows release | READY | Public stable 0.2.5 exists with installer and portable package. |
| Basic Russian install instructions | READY | README contains Russian installation, portable and verification instructions. |
| Release integrity/provenance | READY | Governed hashes and Russian detached-signature evidence exist for the current release. |
| Rights of ООО «Арвектум» | EXTERNAL | Prove the complete exclusive-right chain for all material product code and assets. |
| Rospatent software registration | OPTIONAL | Use as additional evidence if obtained; do not make it the only proof of rights. |
| Corporate/rightsholder qualification | EXTERNAL | Verify ownership/control and other rightsholder conditions under the current rules. |
| APL-IP-002 | READY / HANDOFF | Governed stack/dependency sovereignty inventory exists; remediation is explicitly handed to APL-REG-001B and release-bound legal work to APL-IP-001. |
| Runtime vendor-cloud independence | READY | No mandatory Arvectum API/cloud, telemetry, license server or updater; upstream proxy is user-supplied configuration. |
| Windows offline build capability | READY | Canonical build supports local hash-locked wheelhouse with `--no-index` and `--require-hashes`. |
| APL-IP-001 automation | PARTIAL | Provenance CI exists; complete human review/legal sign-off and freeze evidence for the submitted release after APL-IP-002. |
| Dependency/license inventory | READY / REFRESH | Governed APL-IP-002 inventory exists; refresh/freeze against exact submitted release. |
| SBOM automation | PARTIAL | CycloneDX SBOM CI exists; retain/freeze the SBOM for the exact submitted release and complete legal disposition. |
| THIRD_PARTY_NOTICES | PARTIAL | Notice already exists and distinguishes runtime/build/OS components; reconcile with exact submitted artifacts/license bundle. |
| IP_PROVENANCE | PARTIAL | Automated source manifest exists; complete human/legal review and clean-IP baseline/tag. |
| Foreign payment/dependency evidence | EXTERNAL | Accounting/legal review of applicable foreign payments, licenses, services and rights remains outside the public repo. |
| Source/object-code storage infrastructure | PARTIAL / BLOCKER | GitHub is a foreign lifecycle service; GitVerse is a Russian mirror. APL-REG-001B must establish authoritative Russian-controlled storage evidence. |
| Build/compilation infrastructure | MISSING / BLOCKER | Offline build capability exists, but filing-grade Russian-controlled production CI/build execution and evidence are not yet established. |
| Release/distribution/activation/key infrastructure | PARTIAL / BLOCKER | GitHub Releases is foreign; GitVerse mirror exists. Establish authoritative Russian artifact/distribution path and document absence/presence of activation/key infrastructure. |
| GitVerse | PARTIAL | Russian platform/mirror and candidate sovereign component; mirror existence alone does not prove every infrastructure requirement. |
| Russian-language GUI | PARTIAL | Verify the exact submitted version and remove mandatory untranslated UI where present. |
| Functional characteristics document | PARTIAL | Convert existing technical documentation into expert-facing registry documentation. |
| Install/operation/uninstall manual | PARTIAL | Existing material is substantial but needs a frozen registry-facing manual for the submitted version. |
| Support/maintenance statement | MISSING | Document support, warranty/maintenance and source modification by an eligible Russian entity/person. |
| Price/licensing statement | MISSING | State price or price-determination procedure, or lawful free/open licensing terms, as applicable. |
| Expert test package | MISSING | Prepare a clean test copy plus deterministic installation and verification instructions. |
| Software class | READY / RECHECK | 02.02 — Программы обслуживания; recheck classifier and actual release immediately before filing. |
| Two trusted OSes | MISSING / BLOCKER | For class 02.02 the requirement applies from 2027-01-01 on the current legal baseline. Select and prove two qualifying OSes under APL-REG-001C. |
| Linux runtime/product support | PARTIAL | Linux/Astra tooling exists, but registry compatibility must be proved by actual acceptance tests on two qualifying OSes, not inferred from generic Linux portability. |
| Trusted-OS compatibility protocols | MISSING | Produce repeatable tests and governed evidence for the exact submitted release. |
| Electronic application and UKЭП | EXTERNAL | Submit through the operator's current electronic process using an authorized qualified signature. |

## 5. Work order

### APL-REG-001A — classifier decision — DECIDED

Repository decision: `APL-REG-001A_SOFTWARE_CLASSIFICATION_DECISION.md`.

Current filing position:

- primary class 02.02;
- no additional classes for current scope;
- trusted-OS compatibility date 2027-01-01 under the current rules;
- mandatory final recheck before filing.

### APL-IP-002 — Russian stack & dependency sovereignty audit — COMPLETE

Repository evidence:

- `APL-IP-002_RUSSIAN_STACK_DEPENDENCY_SOVEREIGNTY_AUDIT.md`;
- `compliance/APL_IP_002_STACK_SOVEREIGNTY.json`;
- `tests/test_apl_ip_002_sovereignty_contract.py`;
- `.github/workflows/apl-ip-002-sovereignty.yml`.

Key result: the current application runtime has no mandatory vendor-cloud control plane; the main sovereignty gap is the surrounding source/build/release lifecycle. Production Windows build can already operate from a local hash-locked wheelhouse without PyPI. Lifecycle remediation is now an explicit APL-REG-001B blocker rather than an undefined APL-IP-002 task.

### APL-IP-001 — IP provenance & human-authorship hardening

The automation/provenance foundation already exists. Complete source audit, dependency/license audit, OSS-overlap review, human review of significant modules, remediation where needed, release-bound SBOM, THIRD_PARTY_NOTICES/license bundle, IP_PROVENANCE and clean-IP baseline/tag. Corporate rights documents stay outside the public repository.

### APL-REG-001B — sovereign lifecycle evidence

APL-IP-002 makes this the next infrastructure blocker. Create a precise infrastructure diagram and evidence pack for:

- authoritative Russian source-code storage;
- authoritative Russian object-code/artifact storage;
- controlled Russian compilation/build/CI;
- release publication and distribution;
- activation/licensing/key management if present;
- support, maintenance and source modification.

The production build path must not require GitHub or PyPI availability. Existing offline/hash-locked Windows build capability should be promoted into this controlled path. GitHub can remain an additional collaboration/public channel if legally acceptable, but it is not the sovereign-evidence baseline.

Where current infrastructure fails a mandatory requirement, migrate before submission rather than documenting a known non-compliance.

### APL-REG-001C — trusted Russian OS compatibility

Because 02.02 is now the filing class, plan against the **2027-01-01** applicability date unless the law changes before submission.

- choose two qualifying trusted general-purpose OSes from different rightsholders based on official status at execution time;
- implement the product/runtime/UI packaging needed for them;
- run clean-host installation/start/stop/routing/no-proxy/restart/uninstall/regression tests;
- record OS edition/version, package hashes and exact product commit/release;
- prepare expert-readable compatibility protocols.

Do not hard-code candidate OS brands in the legal contract until their qualifying status is verified at the time of test.

### APL-REG-001D — registry documentation pack

Produce version-frozen Russian documents for:

- product purpose and functional characteristics;
- system requirements;
- installation;
- operation and configuration;
- removal/recovery;
- support and maintenance;
- licensing/price;
- expert test procedure;
- known restrictions and required external proxy configuration.

### APL-REG-001E — private corporate evidence pack

Keep outside the public Git repository:

- charter / applicable EGRUL materials;
- corporate control/ownership evidence where required;
- author/employee/contractor IP transfer documents;
- accounting evidence concerning applicable foreign payments;
- powers/authorizations for the applicant;
- qualified-signature material and credentials.

Never commit private keys, UKЭП material, personal data or restricted corporate evidence.

### APL-REG-001F — pre-submission audit

Immediately before filing:

1. re-check Resolution No. 1236 and the classifier for changes;
2. re-run the APL-REG-001A classification against the exact product release;
3. refresh APL-IP-002 inventory against the exact submitted release and lifecycle;
4. verify every application URL from a clean session;
5. verify all submitted artifact hashes;
6. verify release/version naming is identical across application, manuals and binaries;
7. verify class and trusted-OS evidence;
8. verify rightsholder evidence;
9. freeze the submitted release/evidence set;
10. only then sign and submit the electronic application.

## 6. Relationship to APL-REL-016

APL-REG-001 is an upstream business/compliance dependency of the Russia-first route for obtaining a future National Certification Authority code-signing certificate, to the extent the final NUC eligibility rules require registry inclusion.

Registry inclusion must **not** be represented as proof of Microsoft public trust. APL-REL-016 retains its separate clean-Windows Authenticode/SmartScreen/Smart App Control acceptance gate.

## 7. Acceptance criteria

APL-REG-001 repository preparation can be closed only when:

- class 02.02 remains legally defensible for the exact submitted release after the final recheck;
- every applicable Resolution No. 1236 condition is `PASS` or has a documented `NOT_APPLICABLE` rationale;
- APL-IP-002 inventory is current and final APL-IP-001 human/legal work is complete;
- the exact submitted release has governed dependency, license, SBOM and provenance evidence;
- infrastructure evidence satisfies all requirements applicable on the filing date;
- trusted-OS compatibility is implemented and documented if applicable;
- Russian registry-facing product/support/licensing/test documentation is frozen;
- the private corporate dossier is complete outside the repository;
- a final pre-submission legal/technical re-check has been performed;
- no secret, private key, UKЭП material, personal data or restricted corporate document has been committed.

The external filing and the authority's inclusion decision are tracked separately from repository completion.