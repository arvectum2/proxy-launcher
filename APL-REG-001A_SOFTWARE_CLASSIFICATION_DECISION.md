# APL-REG-001A — Software classification decision

Status: **DECIDED — RECHECK AT SUBMISSION**  
Decision date: **2026-09-13**  
Parent workstream: #46  
Tracking issue: #48

## 1. Decision

For the current Arvectum Proxy Launcher product line, including the public `0.2.x` architecture, use the following registry classification position:

- **Primary class: 02.02 — Программы обслуживания**.
- **Additional classes: none for the current product scope.**

This decision is a filing baseline, not an immutable classification of all future versions. It must be rechecked against the classifier and the actual release functionality immediately before submission.

## 2. Normative classifier baseline

The decision uses the classifier approved by Order of the Ministry of Digital Development, Communications and Mass Media of the Russian Federation dated 2020-09-22 No. 486, in the edition current on the decision date (including the 2023-12-04 No. 1041 amendments).

Relevant class definitions:

- **02.02 — Программы обслуживания**: programs intended to solve auxiliary tasks or provide services of a general nature to users.
- **02.06 — Серверное и связующее программное обеспечение**: software performing service functions at a client's request, providing access to resources/services and enabling interaction between applications/systems/components, including APIs for integration.
- **02.08 — Средства мониторинга и управления**: software measuring, collecting, storing and analysing operating characteristics of managed objects for state assessment, fault detection, alerting and management of settings/state.
- **02.13 — Сетевая операционная система**: software performing network control, subnet definition and traffic routing.

Authoritative/public references used for the decision:

- Order No. 486 / classifier: `https://www.consultant.ru/document/cons_doc_LAW_366474/`
- System software classes: `https://www.consultant.ru/document/cons_doc_LAW_366474/854f2e48e36e690b3570947bf18eddd810ffaa0a/`
- Russian Software Registry: `https://reestr.digital.gov.ru/reestr/`

## 3. Current product facts

The current Proxy Launcher is a user-space desktop utility running on top of an existing general-purpose operating system. Its material functions are:

1. accept user configuration for an upstream HTTP proxy;
2. expose local HTTP and SOCKS5 endpoints for applications on the same workstation;
3. expose/use PAC-based routing support;
4. route configured traffic through the upstream proxy;
5. route destinations matching `no_proxy` rules directly;
6. provide desktop lifecycle/configuration UX for starting, stopping and configuring that local service;
7. package the utility as a Windows installer/portable application, with Linux support being developed separately.

The current product does **not** replace the host operating system, act as router firmware, define network subnets, provide a kernel/network operating-system layer, provide cryptographic VPN protection, act as an NGFW/IDS/IPS/DLP product, or provide a general-purpose enterprise integration platform.

## 4. Functional classification matrix

| Product characteristic | 02.02 Service program | 02.06 Server/middleware | 02.08 Monitoring/management | 02.13 Network OS | 03.* Information security |
|---|---:|---:|---:|---:|---:|
| Runs as utility on existing desktop OS | **strong match** | possible | possible | mismatch | neutral |
| Solves auxiliary/general user networking task | **strong match** | partial | mismatch | partial | mismatch |
| Local HTTP/SOCKS5/PAC endpoints | compatible mechanism | partial match | mismatch | not sufficient | not sufficient |
| Main purpose is integration platform/API | no | **no** | no | no | no |
| Main purpose is telemetry/managed-object monitoring | no | no | **no** | no | no |
| Replaces/acts as network operating system/router firmware | no | no | no | **no** | no |
| Security protection is a principal product function | no | no | no | no | **no** |

Conclusion: **02.02 is the narrowest and most defensible description of the current product's principal purpose.**

## 5. Rejected alternatives

### 5.1 02.13 — Сетевая операционная система

**Rejected for current product scope.**

The wording of 02.13 is broad enough that “traffic routing” alone could create a false positive. Registry practice materially narrows that interpretation: products classified as 02.13 include software routers, router firmware and network operating systems such as:

- registry entry **18442 — Маршрутизатор vESR**, class 02.13;
- registry entry **23194 — Программное обеспечение маршрутизатора «Факел»**, class 02.13;
- embedded router software entries combining 01.03/01.02 with 02.13.

Proxy Launcher is instead an application-layer/user-space proxy-routing utility on a workstation. It does not become a network operating system merely because it forwards selected application traffic.

### 5.2 02.06 — Серверное и связующее программное обеспечение

**Do not claim for `0.2.x`.**

The local HTTP/SOCKS5/PAC listeners perform supporting functions needed by the desktop utility. They are not currently offered as a standalone general-purpose server product, middleware platform, integration bus or API layer between independent enterprise systems.

Reconsider 02.06 only if a future edition gains a separately supported headless/server deployment, multi-user service, stable integration API, central policy service, remote clients, or another independently marketable middleware/server role.

### 5.3 02.08 — Средства мониторинга и управления

**Rejected.**

Proxy Launcher can show or control its own local state, but its principal purpose is not measurement/collection/analysis of operating characteristics of external managed objects, fault detection, alerting or management of an estate of objects.

### 5.4 03.* — Средства обеспечения информационной безопасности

**Rejected.**

A proxy-routing utility is not automatically an information-security product. The current application does not claim or implement an independent protective function such as:

- cryptographic protection or VPN encryption;
- firewall/NGFW enforcement;
- IDS/IPS;
- anti-malware;
- DLP;
- access-control/security-policy enforcement;
- certified channel protection.

Marketing, registry documentation and release notes must not imply SZI/NGFW/VPN certification that does not exist.

### 5.5 05.* — Прикладное программное обеспечение

**Not selected as primary class.**

The product does not solve a domain/business subject-matter task. Its role is auxiliary to applications and user network access, which maps more directly to system software class 02.02.

## 6. Registry analogues — what they prove and what they do not

Registry analogues are used only to understand class boundaries; they are not precedent that binds the expert council.

Observed examples:

| Registry entry | Product | Class | Relevance |
|---:|---|---|---|
| 18442 | Маршрутизатор vESR | 02.13 | Full software router/network routing product; supports rejecting 02.13 for a desktop proxy utility. |
| 23194 | ПО маршрутизатора «Факел» | 02.13 | Router software; supports the same boundary. |
| 28608 / 28249 | Embedded router software | 01.03 + 02.13 | Embedded/appliance context, unlike Proxy Launcher. |

Absence of an exact desktop-proxy analogue is not a reason to over-classify. The classifier definition and principal product purpose control the filing position.

## 7. Regulatory consequence: trusted-OS deadline

Under the Resolution No. 1236 rules as amended by Government Resolution No. 1937, the staged compatibility requirement for **02.02 — Программы обслуживания** applies from **2027-01-01**.

Therefore the engineering/compliance plan treats the following as a hard pre-submission blocker for filings subject to that requirement:

- actual compatibility with at least two operating systems satisfying the applicable trusted-software requirements;
- the two OS products must satisfy the rightsholder/distinctness rules applicable at the time;
- compatibility must be demonstrated on the exact release being submitted, not inferred from Python or generic Linux portability;
- evidence must record OS names/versions, product version/hash, installation, startup, proxy routing, direct/no-proxy routing, restart and removal behaviour.

APL-REG-001C owns that evidence.

## 8. Reclassification triggers

Re-open APL-REG-001A before filing if any of the following becomes a material product function:

- TUN/TAP or packet-level IP routing as a system network layer;
- software-router/appliance mode controlling subnets/interfaces/routes;
- kernel driver or host network-stack replacement/control becoming the core product;
- central multi-user proxy/server deployment marketed independently from the desktop launcher;
- public integration API/middleware role between independent systems;
- firewall, filtering/security-policy engine, IDS/IPS or access-control enforcement;
- VPN/cryptographic channel protection;
- telemetry/monitoring/management of an external fleet becoming a principal function;
- a new classifier edition changes the relevant class definitions.

Application-based routing/exclusions alone do **not** automatically trigger 02.13 or 03.*; the actual architecture and principal purpose must be reassessed at that time.

## 9. Filing language

Recommended short class justification for the registry dossier:

> Arvectum Proxy Launcher является программой обслуживания общего назначения, работающей поверх операционной системы пользователя. Программа обеспечивает настройку и локальное предоставление HTTP/SOCKS5/PAC-сервисов для направления пользовательского прикладного трафика через заданный upstream proxy либо напрямую по правилам исключений. Программа не является операционной системой, программным маршрутизатором/прошивкой сетевого оборудования или средством криптографической и иной защиты информации.

The final Russian wording must be checked against the exact submitted version and classifier immediately before filing.

## 10. Acceptance

APL-REG-001A is complete at repository level when:

- primary class 02.02 is recorded;
- additional classes are intentionally empty for current scope;
- rejected alternatives and reasons are recorded;
- registry boundary examples are recorded;
- the 2027-01-01 trusted-OS deadline is propagated into APL-REG-001;
- reclassification triggers are explicit;
- ordinary repository checks pass.
