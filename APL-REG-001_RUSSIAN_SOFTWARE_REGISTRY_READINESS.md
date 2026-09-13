# APL-REG-001 — Russian Software Registry readiness

Status: **PRE-SUBMISSION WORKSTREAM OPEN**  
Audit date: **2026-09-13**  
Baseline: `main` @ `6731e739534c4d3bd9f22fee94a5bb7c92ca5083`  
Tracking issue: #46

## 1. Goal and boundary

Prepare Arvectum Proxy Launcher and the ООО «Арвектум» evidence package for an application to the Unified Register of Russian Programs for Computers and Databases under the rules established by Government Resolution No. 1236 in the edition effective on the audit date.

Repository changes can make the product **application-ready**. Inclusion in the register itself is an external decision of the competent authority/expert process and is not a repository acceptance criterion.

## 2. Regulatory baseline

The pre-submission review must use the law actually effective on the submission date. The baseline for this document is:

- Government Resolution of the Russian Federation No. 1236 of 2015-11-16, edition including amendments effective through 2026-09-13;
- Government Resolution No. 1937 of 2025-11-28, effective from 2026-03-01, including staged trusted-OS compatibility requirements;
- Government Resolution No. 1007 of 2026-08-13, whose relevant amendments to the register rules are effective from 2026-09-01;
- the software classifier and its application rules effective on the actual submission date.

### 2.1 Rospatent is evidence, not a gate

A Rospatent software-registration certificate can strengthen the evidence package, but APL-REG-001 does not treat Rospatent registration as a mandatory prerequisite to a registry application. The controlling gate is evidence that the exclusive right and the rightsholder satisfy the applicable requirements of Resolution No. 1236.

### 2.2 Trusted-OS compatibility changes the delivery plan

Resolution No. 1937 introduced a requirement for affected software to be compatible with at least two operating systems meeting the statutory trusted-software requirements, subject to the exceptions in the rules. The requirement is staged by software category:

- office software: 2026-09-01;
- service programs and several system/infrastructure classes: 2027-01-01;
- application software, industry application software and information-security software: 2027-06-01;
- industrial software and organization-process management software: 2028-01-01.

The exact date for Proxy Launcher therefore depends on its legally defensible classifier assignment. That classification is a blocking decision, not a cosmetic metadata choice.

## 3. Product classification policy

Current public product description: Arvectum Proxy Launcher is a local client that routes traffic through a configured upstream HTTP proxy while exposing local HTTP, SOCKS5 and PAC endpoints; `no_proxy` rules can route selected destinations directly.

Do **not** classify the product as information-security software merely because it works with network traffic or proxies. The current product is not represented as a cryptographic VPN, firewall, certified security product or channel-protection product.

Working hypothesis only: a system/service/network utility class may be more appropriate. Before submission, APL-REG-001A must compare the real release functionality against the classifier effective on that date and record:

1. primary class;
2. any defensible additional class;
3. rejected candidate classes and why;
4. date on which the two-trusted-OS requirement becomes applicable;
5. whether any class-specific evidence or certification is triggered.

No application should be submitted while this decision remains unresolved.

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
| APL-IP-002 | MISSING | Complete Russian stack & dependency sovereignty audit first. |
| APL-IP-001 | MISSING | Complete IP provenance / human-authorship hardening after APL-IP-002. |
| Dependency/license inventory | MISSING | Produce governed runtime/build/dev inventory and license disposition. |
| SBOM | MISSING | Produce SBOM tied to the exact submitted release. |
| THIRD_PARTY_NOTICES | MISSING | Produce notices for redistributed third-party components. |
| IP_PROVENANCE | MISSING | Produce provenance record and clean-IP baseline/tag. |
| Foreign payment/dependency evidence | MISSING | Accounting/legal review of applicable foreign payments, licenses, services and rights. |
| Source/object-code storage infrastructure | PARTIAL | Inventory physical hosting/control and map it to Resolution No. 1236 requirements. |
| Build/compilation infrastructure | PARTIAL | Document where the submitted release is compiled and retain auditable build evidence. |
| Release/distribution/activation/key infrastructure | PARTIAL | Inventory and document; do not assume GitHub alone satisfies Russian-infrastructure rules. |
| GitVerse | PARTIAL | Useful sovereign mirror/evidence channel, but mirror existence alone does not prove every infrastructure requirement. |
| Russian-language GUI | PARTIAL | Verify the exact submitted version and remove mandatory untranslated UI where present. |
| Functional characteristics document | PARTIAL | Convert existing technical documentation into expert-facing registry documentation. |
| Install/operation/uninstall manual | PARTIAL | Existing material is substantial but needs a frozen registry-facing manual for the submitted version. |
| Support/maintenance statement | MISSING | Document support, warranty/maintenance and source modification by an eligible Russian entity/person. |
| Price/licensing statement | MISSING | State price or price-determination procedure, or lawful free/open licensing terms, as applicable. |
| Expert test package | MISSING | Prepare a clean test copy plus deterministic installation and verification instructions. |
| Software class | MISSING / BLOCKER | Complete APL-REG-001A before filing. |
| Two trusted OSes | MISSING / BLOCKER | Select two qualifying OSes of different rightsholders when the requirement applies. |
| Linux runtime/product support | PARTIAL | Cross-platform work is in the roadmap, but registry compatibility must be proved by actual acceptance tests, not inferred from Python portability. |
| Trusted-OS compatibility protocols | MISSING | Produce repeatable tests and signed/controlled evidence for the exact release. |
| Electronic application and UKЭП | EXTERNAL | Submit through the operator's current electronic process using an authorized qualified signature. |

## 5. Work order

### APL-REG-001A — classifier decision

- obtain the classifier/rules effective on execution date;
- map each material Proxy Launcher function to candidate classes;
- reject overbroad/security classifications unsupported by functionality;
- determine the staged trusted-OS deadline;
- freeze the result as registry evidence.

### APL-IP-002 — Russian stack & dependency sovereignty audit

Must precede IP hardening. Inventory runtime/build/dev dependencies, origin, rightsholder, license, redistribution, network dependency, criticality, Russian analogue and replacement feasibility. Also inventory source/build/release infrastructure relevant to Resolution No. 1236.

### APL-IP-001 — IP provenance & human-authorship hardening

Complete source audit, dependency/license audit, OSS-overlap review, human review of significant modules, remediation where needed, SBOM, THIRD_PARTY_NOTICES, IP_PROVENANCE and clean-IP baseline/tag. Corporate rights documents stay outside the public repository.

### APL-REG-001B — sovereign lifecycle evidence

Create a precise infrastructure diagram and evidence pack for:

- source-code storage;
- object-code/artifact storage;
- compilation/build;
- release publication and distribution;
- activation/licensing/key management if present;
- support, maintenance and source modification.

Where current infrastructure fails a mandatory requirement, migrate before submission rather than documenting a known non-compliance.

### APL-REG-001C — trusted Russian OS compatibility

After classification establishes the applicable deadline:

- choose two qualifying trusted general-purpose OSes from different rightsholders based on the official status at execution time;
- implement the product/runtime/UI packaging needed for them;
- run clean-host installation/start/stop/routing/no-proxy/uninstall/regression tests;
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
2. verify every application URL from a clean session;
3. verify all submitted artifact hashes;
4. verify release/version naming is identical across application, manuals and binaries;
5. verify class and trusted-OS evidence;
6. verify rightsholder evidence;
7. freeze the submitted release/evidence set;
8. only then sign and submit the electronic application.

## 6. Relationship to APL-REL-016

APL-REG-001 is now an upstream business/compliance dependency of the Russia-first route for obtaining a future National Certification Authority code-signing certificate, to the extent the final NUC eligibility rules require registry inclusion.

Registry inclusion must **not** be represented as proof of Microsoft public trust. APL-REL-016 retains its separate clean-Windows Authenticode/SmartScreen/Smart App Control acceptance gate.

## 7. Acceptance criteria

APL-REG-001 repository preparation can be closed only when:

- a legally defensible software class is recorded;
- every applicable Resolution No. 1236 condition is `PASS` or has a documented `NOT_APPLICABLE` rationale;
- APL-IP-002 and APL-IP-001 are complete;
- the exact submitted release has governed dependency, license, SBOM and provenance evidence;
- infrastructure evidence satisfies all requirements applicable on the filing date;
- trusted-OS compatibility is implemented and documented if applicable;
- Russian registry-facing product/support/licensing/test documentation is frozen;
- the private corporate dossier is complete outside the repository;
- a final pre-submission legal/technical re-check has been performed;
- no secret, private key, UKЭП material, personal data or restricted corporate document has been committed.

The external filing and the authority's inclusion decision are tracked separately from repository completion.