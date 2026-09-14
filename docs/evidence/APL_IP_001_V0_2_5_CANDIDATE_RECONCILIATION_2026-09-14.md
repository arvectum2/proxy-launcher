# APL-IP-001 — v0.2.5 candidate reconciliation

Date: 2026-09-14  
Tracking: #57  
Verdict: **CONDITIONAL — ENGINEERING RECONCILED / HUMAN-LEGAL GATE OPEN**

## 1. Why a new reconciliation is required

The prior canonical APL-IP-001 sign-off packet was bound to a `0.2.3` candidate (`adc917e905acca1f8e97d560a3363b07adc279fb`). It cannot be silently carried forward to the accepted `0.2.5` release because product/runtime and installer lifecycle code changed after that candidate.

This record binds the engineering evidence to the accepted `0.2.5` object without manufacturing legal approval.

## 2. Exact accepted v0.2.5 identity

- accepted product-source commit: `9e8ca7e851563082cd7d03d7543ccb360a37ec27`;
- accepted source tree: `12eb128762ba4e50d12af35c681aa80d0818e19a`;
- immutable release tag: `v0.2.5`;
- tag commit: `6509d5e7228a90bb5c0b779ea6e2b9df0e9d0d85`;
- accepted application SHA-256: `1ab36b7a6a0a225dcf06fb2c630d0d2ba47ec17578dbd5949f08e992853d653c`;
- accepted Setup SHA-256: `9b5368d67874b7164ee56a245c75db4b23af593a1d72f7e947774516abcc95e3`;
- physical acceptance evidence SHA-256: `2afe6af76a69dc4d0b6869385dda6c4467c3d01e38997a04ca554c28aa24021a`.

`v0.2.5` is immutable. This work does not move the tag, replace assets or alter accepted PE bytes.

## 3. Source-drift review from historical 0.2.3 candidate

The repository comparison from `adc917e...` to accepted source `9e8ca7e...` contains substantial QA/release/governance work and a bounded set of material product-source changes.

### `application_filesystem.py`

Reviewed change: canonical installed executable location moved from the historical Documents location to `%LOCALAPPDATA%/Programs/ArvectumProxyLauncher`, while explicit historical-path helpers preserve migration/recovery compatibility.

Engineering classification: **stable-location and legacy-migration hardening**. No obvious third-party source import was identified in the reviewed delta. A human factual carry-forward is still required for authorship/control.

### `portable_lifecycle.py`

Reviewed change: stable-copy handling follows the LocalAppData location and maintenance commands such as stop/status/rollback avoid asynchronous self-handoff so callers can observe the exact lifecycle operation.

Engineering classification: **maintenance handoff/lifecycle safety**. No obvious third-party source import was identified in the reviewed delta. Human factual carry-forward remains required.

### `proxy_core.py`

Reviewed change: bounded version/comment metadata update from the historical release line to `0.2.5`.

Engineering classification: **version metadata update**. Human factual carry-forward remains required even though the delta is trivial.

### `recovery_autostart.py`

Reviewed change: migration/recovery discovery recognizes the current stable directory and the historical Documents directory; diagnostic wording follows the new stable location.

Engineering classification: **legacy-location migration update**. No obvious third-party source import was identified in the reviewed delta. Human factual carry-forward remains required.

### Installer/release code

Material installer lifecycle changes include:

- `installer/ArvectumProxyLauncher.iss`;
- `installer/uninstall_helper.ps1`;
- `installer/upgrade_helper.ps1`.

These are tied to the exact accepted v0.2.5 release through the existing release/physical-acceptance evidence and repository tests. That engineering evidence does not itself prove legal authorship; R-4 below remains the human factual boundary.

## 4. Accepted source → tag → current main

Two separate comparisons were reviewed:

1. accepted product source `9e8ca7e...` → immutable tag commit `6509d5e...`: release/evidence/governance changes, no material product-runtime source change;
2. tag commit `6509d5e...` → reconciliation-start main `310a671...`: compliance, signing, registry, Astra, QA and release tooling changes, with no change to the accepted v0.2.5 product-runtime object.

Therefore this reconciliation can bind the immutable v0.2.5 identity while later repository governance work continues independently.

## 5. Exact provenance evidence

The exact accepted product-source commit was processed by the existing APL-IP-001 provenance workflow:

- workflow run: `34720855901`;
- source SHA: `9e8ca7e851563082cd7d03d7543ccb360a37ec27`;
- artifact ID: `10306615531`;
- artifact: `apl-ip-001-source-provenance`;
- GitHub artifact digest: `sha256:5a502a7ab674ea395828130b1724fa134ce7b4c62b032d7dbf1c45305f449db0`;
- result: **SUCCESS**.

The manifest is engineering evidence only. A zero-finding/valid manifest is not a copyright certificate and does not prove ownership.

## 6. Exact SBOM evidence

The accepted source was also processed by the CycloneDX workflow:

- workflow run: `34720856022`;
- source SHA: `9e8ca7e851563082cd7d03d7543ccb360a37ec27`;
- artifact ID: `10306326080`;
- artifact: `arvectum-proxy-launcher-sbom-9e8ca7e851563082cd7d03d7543ccb360a37ec27`;
- GitHub artifact archive digest: `sha256:102e2b6a3a9f509aef6881b179aaab6e5ada6593b62d465a27c627885c27060e`;
- result: **SUCCESS**.

This is the build-dependency SBOM boundary. It must not be described as a complete legal inventory of every operating-system component or every byte in every cross-platform package.

## 7. Third-party / OSS boundary

The current governed boundary is `THIRD_PARTY_NOTICES.txt` plus APL-IP-002. Foreign or international OSS is not treated as automatically disqualifying; the relevant questions are license compliance, actual inclusion, distribution obligations and rights.

The engineering review found no newly introduced obvious external source block in the bounded product-source drift above. This statement is not an exhaustive legal similarity opinion. Historical human factual provenance remains evidence, while the v0.2.5 carry-forward must be explicitly confirmed by an authorized human under R-4.

AppImage remains **HOLD / excluded from the current clean-IP approval scope** until its separately bounded runtime-license obligations are deliberately cleared for a promoted commercial distribution.

## 8. Human/legal gates

The repository must remain fail-closed on these facts:

- **R-1 — HUMAN REQUIRED:** verify an executed author → ООО «Арвектум» rights basis covering the exact v0.2.5 object;
- **R-2 — HUMAN REQUIRED:** verify factual Rospatent status if it is relied upon;
- **R-3 — HUMAN REQUIRED:** verify applicable corporate approval/exception basis;
- **R-4 — HUMAN REQUIRED:** an authorized human must explicitly carry forward the factual authorship/creative-control statements to the reviewed v0.2.5 source drift and selected release scope.

## 9. Decision

Engineering reconciliation: **PASS**.  
Automated provenance/SBOM binding: **PASS**.  
Human/legal disposition: **PENDING**.  
Overall APL-IP-001 v0.2.5 verdict: **CONDITIONAL_HUMAN_LEGAL_GATE**.

**NO CLEAN-IP TAG IS AUTHORIZED BY THIS RECORD.** A clean-IP/legal baseline tag may be created only after the required human/legal gates are actually completed and the canonical sign-off record is changed to an explicit approved state by an authorized person.
