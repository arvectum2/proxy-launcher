# APL-REG-001 — Russian Software Register readiness

Updated: 2026-09-17  
Current product release: **Arvectum Proxy Launcher 0.2.9**  
Primary class: **02.02 — Программы обслуживания**  
Filing status: **PRE-SUBMISSION / HOLD**

## Current position

The repository-side registration work has advanced beyond the original 2026-09-14 hold:

- APL-REG-001A classifier decision: **complete** — class 02.02, no additional class for current scope.
- APL-REG-001B sovereign lifecycle contract/tooling: **complete in repository; physical Russian perimeter evidence still open**.
- APL-REG-001C Astra Linux + RED ОС compatibility engineering: **physical compatibility demonstrated**. Astra Linux SE physical acceptance was closed in the APL-LNX-010 line; RED ОС 8.0.3 physical acceptance was closed by PR #83 with 62/62 focused regressions.
- APL-REG-001D filing documentation: **prepared** under `docs/registry/` for `v0.2.9`.
- APL-REG-001E private evidence checklist: **prepared; private evidence itself remains HUMAN/legal work**.
- APL-REG-001F pre-submission audit: **prepared; filing remains HOLD until real blockers close**.

## Current legal timing baseline

Government Resolution No. 1937 dated 2025-11-28 introduces the two-trusted-OS compatibility condition into Resolution No. 1236 and applies it to the `Программы обслуживания` class from **2027-01-01**. Re-check the current law and the trusted-software status of the exact selected Astra/RED editions immediately before filing.

## Filing blockers

| Gate | Status | Required closure |
|---|---|---|
| G1 — exclusive-right chain to ООО «Арвектум» | BLOCKED / HUMAN-LEGAL | Executed, effective evidence covering the current submitted object. MIT/Copyright text is not a substitute. |
| G2 — Russian source/build/storage/distribution perimeter | BLOCKED / PHYSICAL | Execute APL-REG-001B on real Russian-controlled infrastructure and retain filing-grade evidence. |
| G3 — exact submitted Linux release evidence | BLOCKED / PRE-SUBMIT | Physical smoke/acceptance of exact public `v0.2.9` DEB on Astra and RPM on RED ОС, or an explicitly approved legal/technical traceability basis for unchanged Linux payload. Re-run is preferred. |
| G4 — trusted-OS legal status | VERIFY | Confirm current qualifying status/records of the selected exact OS products on filing date. |
| G5 — corporate data, authority and УКЭП | BLOCKED / PRIVATE-HUMAN | Current EGRUL facts, signer authority, contacts, required corporate/accounting declarations, qualified signature. |
| G6 — live portal recheck | BLOCKED until filing session | Reconcile worksheet with the current `reestr.digital.gov.ru` form and current No. 1236 wording immediately before signing. |

## Version evidence nuance

The RED ОС physical acceptance record is bound to exact public `v0.2.8`. Release `v0.2.9` is a Windows rollback/recovery release and its release notes state that Linux behavior from `0.2.8` is retained unchanged. That is useful traceability, but this dossier deliberately does **not** mislabel it as a physical execution of exact `v0.2.9` Linux packages.

For the strongest filing evidence, re-run the shortened expert procedure against the canonical public `v0.2.9` DEB/RPM and record exact SHA-256 values and OS versions.

## Registry documentation pack

See `docs/registry/README.md` for the index. The pack contains:

- portal/application worksheet;
- functional characteristics;
- installation/operation/removal/recovery manual;
- support/maintenance statement;
- licensing/price statement;
- expert test procedure;
- private evidence checklist;
- pre-submission audit.

## Public/current distribution facts

`v0.2.9` publishes:

- Windows x64 Setup;
- Windows x64 portable ZIP;
- Astra Linux 1.8 x86-64 DEB;
- RED ОС 8.0.3 x86-64 RPM;
- `SHA256SUMS.txt`.

GitHub is the current canonical public release source. GitVerse is an independent Russian mirror and transports package formats disallowed by its release UI inside deterministic one-file ZIP wrappers without changing the enclosed canonical package bytes.

The release does not claim Authenticode and does not automatically carry forward the historical detached CryptoPro/Rutoken signature from `v0.2.5`.

## Safety rule

Do not submit or sign the external application while `docs/registry/APL_REG_001F_PRE_SUBMISSION_AUDIT.md` is HOLD. Repository automation must not invent corporate/legal facts, certificates, trusted-OS status, private evidence or signer authority.
