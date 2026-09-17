# APL-REG-001 — Russian Software Register readiness

Updated: 2026-09-17  
Current release: **Arvectum Proxy Launcher 0.2.9**  
Primary class: **02.02 — Программы обслуживания**  
Filing status: **PRE-SUBMISSION / HOLD**

## Completed repository work

- APL-REG-001A classifier decision: complete — class 02.02.
- APL-REG-001B sovereign lifecycle contract/tooling: repository tooling complete; physical Russian perimeter evidence open.
- APL-REG-001C compatibility engineering: physical Astra Linux SE + RED ОС compatibility base complete; RED ОС PR #83 closed with 62/62 focused regressions.
- APL-REG-001D filing documentation: prepared under `docs/registry/` and frozen to `v0.2.9`.
- APL-REG-001E private evidence checklist: prepared; evidence remains private/HUMAN.
- APL-REG-001F pre-submission audit: prepared and intentionally HOLD.

## Current mandatory gates under Rule 1236

The filing package must demonstrate the actual criteria in point 5, not just engineering quality. Open gates visible from the public repository are:

1. **rights/rightsholder control** — executed exclusive-right basis and current corporate-control facts;
2. **foreign-payment ratio** — private accounting evidence for the <30% criterion;
3. **Russian support/modification** — identify and substantiate the eligible Russian support/development party;
4. **Russian technical infrastructure** — source/object storage and compilation technical means physically in RF; release/distribution technical means in RF and Russian-controlled;
5. **Russian GUI** — verify exact `v0.2.9` user-facing surface;
6. **corporate applicant/signature** — contacts, signer authority and qualified electronic signature;
7. **final live-form/current-law check** immediately before signing.

The repository also documents absence of a mandatory Arvectum cloud/control plane, license server and forced updater for the current product scope; upstream proxy is user/customer supplied.

## Trusted-OS timing

Point 5 «м» introduces compatibility with at least two trusted operating systems. Government Resolution No. 1937 dated 2025-11-28 applies that requirement to the **«Программы обслуживания»** class from **2027-01-01**.

Therefore two-trusted-OS compatibility is **not yet a current filing criterion for class 02.02 on 2026-09-17**. It is nevertheless a near-term lifecycle gate. Existing physical Astra Linux SE + RED ОС acceptance provides a strong base; an exact public `v0.2.9` DEB/RPM smoke and current trusted-status verification are recommended before 2027.

## Exact-release nuance

RED ОС physical acceptance is bound to exact public `v0.2.8`. Release `v0.2.9` changed Windows rollback/recovery and states that Linux behavior from `0.2.8` is retained unchanged. The dossier does not mislabel the prior run as exact-0.2.9 execution.

## Registry dossier

See `docs/registry/README.md`. It includes:

- application-field worksheet;
- Rule 1236 compliance matrix;
- functional characteristics;
- installation/operation/removal/recovery manual;
- support/maintenance statement;
- technical-infrastructure description;
- license/price statement;
- expert verification procedure;
- private evidence checklist;
- pre-submission audit.

## Current distribution facts

`v0.2.9` publishes Windows Setup, Windows portable ZIP, Astra DEB, RED ОС RPM and `SHA256SUMS.txt`. GitHub is the current canonical public release source; GitVerse is an independent Russian mirror. Neither a public GitHub workflow nor mirror existence is treated as proof of the physical Russian filing perimeter required by point 5 «и»/«к».

## Safety rule

Do not submit or sign the external application while `docs/registry/APL_REG_001F_PRE_SUBMISSION_AUDIT.md` is HOLD. Repository automation must not invent corporate/legal/accounting facts, infrastructure location/control, certificates, trusted-OS status or signer authority.
