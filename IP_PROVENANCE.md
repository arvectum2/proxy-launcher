# IP_PROVENANCE.md — Arvectum Proxy Launcher source provenance

Status: **v0.2.5 ENGINEERING RECONCILED / HUMAN-LEGAL SIGN-OFF PENDING**

This record defines the repository provenance boundary for APL-IP-001. Automated scans, Git history and AI review are engineering evidence; none of them by themselves prove copyright authorship, exclusive ownership or legal approval.

The current canonical v0.2.5 reconciliation is `docs/evidence/APL_IP_001_V0_2_5_CANDIDATE_RECONCILIATION_2026-09-14.md`. The execution-ready human/legal decision record is `docs/APL_IP_001_V0_2_5_SIGNOFF.md`. Historical 0.2.3 sign-off files remain historical evidence and are superseded for current release identity.

## Exact v0.2.5 boundary

- accepted product-source commit: `9e8ca7e851563082cd7d03d7543ccb360a37ec27`;
- accepted source tree: `12eb128762ba4e50d12af35c681aa80d0818e19a`;
- immutable tag: `v0.2.5`;
- tag commit: `6509d5e7228a90bb5c0b779ea6e2b9df0e9d0d85`;
- accepted application SHA-256: `1ab36b7a6a0a225dcf06fb2c630d0d2ba47ec17578dbd5949f08e992853d653c`;
- accepted Setup SHA-256: `9b5368d67874b7164ee56a245c75db4b23af593a1d72f7e947774516abcc95e3`.

`v0.2.5` is immutable. **Git history must not be rewritten** to manufacture provenance, and this work must not move the tag or replace accepted release bytes.

## Repository-authored source boundary

Arvectum product/repository source includes top-level Python product modules, platform backends/runtime/preflight/diagnostics/autostart modules, PowerShell/shell build and release scripts, Inno Setup configuration, tests, GitHub/GitVerse CI definitions, product documentation and Arvectum-created visual assets.

No third-party source tree is intentionally treated as Arvectum-owned merely because it is present in a build or release. Third-party components are governed through SBOM, `THIRD_PARTY_NOTICES.txt`, APL-IP-002 and exact platform/release evidence.

## v0.2.5 drift reconciliation

The historical post-0.2.3 review candidate `adc917e905acca1f8e97d560a3363b07adc279fb` predates material v0.2.5 work and cannot serve as the current clean-IP object without reconciliation.

The bounded material runtime-source drift reviewed for v0.2.5 is:

- `application_filesystem.py` — stable-location and legacy-migration hardening;
- `portable_lifecycle.py` — maintenance handoff/lifecycle safety;
- `proxy_core.py` — version metadata update;
- `recovery_autostart.py` — legacy-location migration update.

Material installer lifecycle drift includes `installer/ArvectumProxyLauncher.iss`, `installer/uninstall_helper.ps1` and `installer/upgrade_helper.ps1` and is additionally bound to exact v0.2.5 release/physical-acceptance evidence.

Engineering review found no obvious external source import in the bounded runtime drift. That is not an exhaustive legal similarity opinion. The historical human factual provenance must be explicitly carried forward to this exact v0.2.5 object by an authorized human under R-4.

No material product-runtime source changed between accepted source `9e8ca7e...` and immutable tag `6509d5e...`, nor between that tag and the reconciliation-start main `310a671...`; later changes are governance/compliance/signing/QA/release tooling.

## Automated provenance evidence

`tools/ip_provenance_check.py`:

1. obtains the version-controlled source inventory from `git ls-files`;
2. hashes each governed source/build/config file with SHA-256;
3. records size, path and source category in a deterministic JSON manifest;
4. surfaces header-style third-party/generated-code markers for review;
5. always records `human_review_required=true` and `legal_signoff_required=true`.

For the exact accepted product-source commit, the successful provenance evidence is:

- workflow run `34720855901`;
- artifact ID `10306615531` (`apl-ip-001-source-provenance`);
- GitHub artifact digest `sha256:5a502a7ab674ea395828130b1724fa134ce7b4c62b032d7dbf1c45305f449db0`.

A valid or zero-finding manifest is not a copyright certificate.

## SBOM / third-party boundary

The exact accepted source also has successful CycloneDX evidence:

- workflow run `34720856022`;
- artifact ID `10306326080`;
- artifact `arvectum-proxy-launcher-sbom-9e8ca7e851563082cd7d03d7543ccb360a37ec27`;
- GitHub artifact archive digest `sha256:102e2b6a3a9f509aef6881b179aaab6e5ada6593b62d465a27c627885c27060e`.

The repository SBOM is a build-dependency SBOM and must not be misrepresented as a complete cross-platform shipped-payload inventory.

The governed third-party boundary includes CPython/Python stdlib, Tcl/Tk, PyInstaller and build dependencies, Inno Setup, host OS components/APIs and other items documented by `THIRD_PARTY_NOTICES.txt` and APL-IP-002. Foreign/international OSS is not automatically treated as a registry or IP failure; actual rights/license/distribution obligations govern.

AppImage remains **HOLD / excluded from the current clean-IP approval scope** until its separately bounded type-2 runtime obligations are deliberately cleared for promoted distribution.

## Human-authorship / legal boundary

Historical factual provenance records human creative control, base-logo authorship, no deliberate copying from external projects, and human review/acceptance or correction of AI-assisted code. Those historical facts are evidence, not an automatic legal carry-forward.

The exact v0.2.5 object remains blocked on:

- **R-1:** executed author → ООО «Арвектум» rights basis covering the exact v0.2.5 object;
- **R-2:** factual Rospatent status if relied upon;
- **R-3:** applicable corporate approval/exception basis;
- **R-4:** authorized human factual carry-forward for the material v0.2.5 changes and selected release scope.

The execution-ready rights-basis template is `docs/legal/APL_IP_001_RIGHTS_ASSIGNMENT_V0_2_5_CANDIDATE_ADDENDUM_2026-09-14.md`. Repository presence does not mean it has been executed.

## Baseline verdict

- Automated source inventory/hash manifest: **IMPLEMENTED**.
- APL-IP-003 engineering refactor: **COMPLETE**.
- APL-IP-002 dependency/sovereignty inventory: **COMPLETE / release refresh required**.
- Exact v0.2.5 provenance binding: **PASS**.
- Exact v0.2.5 build-SBOM binding: **PASS**.
- v0.2.5 bounded runtime-source drift engineering review: **PASS / HUMAN FACTUAL CARRY-FORWARD REQUIRED**.
- Third-party notices/release boundary: **IMPLEMENTED / exact scope review required**.
- AppImage promoted distribution: **HOLD / OUT OF CURRENT APPROVAL SCOPE**.
- R-1 through R-4: **PENDING — HUMAN/LEGAL ACTION**.
- Overall machine verdict: **CONDITIONAL_HUMAN_LEGAL_GATE**.
- **Clean IP baseline/tag:** **BLOCKED** until the required human/legal review is genuinely completed.

**NO CLEAN-IP TAG IS AUTHORIZED BY AUTOMATION OR THIS RECORD.** It may be created only after actual human/legal completion and explicit approval of the exact object; the immutable `v0.2.5` tag itself must never be moved.
