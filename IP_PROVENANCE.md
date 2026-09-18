# IP_PROVENANCE.md — Arvectum Proxy Launcher source provenance

Status: **v0.2.9 FILING-EVIDENCE COMPLETE / OPTIONAL EXTERNAL LEGAL HARDENING**

Separate legal-baseline status: **HUMAN-LEGAL SIGN-OFF PENDING** only if a distinct clean-IP/legal baseline is deliberately requested. This is not a blocker for the current registry filing-evidence packet.

This record defines the repository provenance boundary for APL-IP-001. Automated scans, Git history, CI and AI review are engineering evidence; none of them by themselves prove copyright authorship, exclusive ownership or legal approval.

The current canonical reconciliation is `docs/evidence/APL_IP_001_V0_2_9_CANDIDATE_RECONCILIATION_2026-09-18.md`. The current human/legal decision record is `docs/APL_IP_001_V0_2_9_SIGNOFF.md`.

The former v0.2.5 packet remains immutable historical provenance and physical-acceptance evidence. It is no longer the final filing/current-release sign-off object.

## Exact v0.2.9 boundary

- accepted product-source commit: `ca7c1019e78cb3ee1e57173f2b58ecea0c27b919`;
- accepted source tree: `55f2d50f96387e5d55583ac90ca3d0b48f80ce99`;
- immutable tag: `v0.2.9`;
- annotated tag object: `59dfd56191c8d9aa0e71a9fba2d86baaaf843520`;
- tag commit: `d13d9dac2ae2439c2fe70d32e1b168df320a9bd2`;
- tag tree: `55f2d50f96387e5d55583ac90ca3d0b48f80ce99`.

The accepted PR head and final tag commit resolve to the exact same tree.

Promoted package SHA-256:

- Windows portable ZIP: `6f541b28c08834170258b48e27ffeafc6a0ad0e9c3a27760ec02cc7d01a305d0`;
- Windows Setup: `a483c64205ad8a0d7a2e53e795714dd67d30c5c95f70f231d05a45b6f6db425c`;
- Astra Linux DEB: `f1bdb58ed4dad02bcc391ae88c8102062a2ed75860f5735cbe45dd6569d77711`;
- RED OS RPM: `59a3a45562da3c65691e901471bdaab16f0de94f5bbc4dfa786f524d417660fc`.

Existing release tags and published release bytes are immutable evidence objects and must not be rewritten. **Git history must not be rewritten** to manufacture or improve the appearance of provenance.

## Historical v0.2.5 anchor

v0.2.5 remains the first physically sealed Windows CFA-safe provenance/acceptance anchor:

- historical tag commit: `6509d5e7228a90bb5c0b779ea6e2b9df0e9d0d85`;
- historical sign-off packet: `docs/APL_IP_001_V0_2_5_SIGNOFF.md`;
- historical reconciliation: `docs/evidence/APL_IP_001_V0_2_5_CANDIDATE_RECONCILIATION_2026-09-14.md`.

Those files are preserved as evidence rather than repurposed as the current v0.2.9 decision.

## Repository-authored source boundary

Arvectum product/repository source includes top-level Python product modules, platform backends/runtime/preflight/diagnostics/autostart modules, PowerShell/shell build and release scripts, Inno Setup configuration, tests, CI definitions, product documentation and Arvectum-created visual assets.

No third-party source tree is treated as Arvectum-owned merely because it is present in a build or release. Third-party components remain governed by SBOM, `THIRD_PARTY_NOTICES.txt`, APL-IP-002 and exact platform/release evidence.

## v0.2.5 -> v0.2.9 material evolution

The current release is 135 commits ahead of v0.2.5. Material product changes are grouped as follows:

- v0.2.5 -> v0.2.6: Astra/Linux runtime, desktop-proxy, diagnostics and packaging expansion;
- v0.2.6 -> v0.2.7: RED OS/KDE/RPM platform expansion;
- v0.2.7 -> v0.2.8: Linux mixed-state recovery hardening;
- v0.2.8 -> v0.2.9: Windows saved-or-Arvectum rollback ownership symmetry.

The exact paths and classification are recorded in the current reconciliation. This engineering classification does not replace a human authorship/rights review.

The dependency lock did not change across v0.2.5..v0.2.9.

## Automated provenance evidence

The final PR head `ca7c1019...`, the pull-request synthetic merge `1f4658c509a8b285461f212d0b9c5cbb08583a92` and the release tag commit `d13d9dac...` resolve to the same exact tree `55f2d50f...`.

Exact-tree provenance evidence:

- workflow run `35255499712`;
- artifact ID `10511679846` (`apl-ip-001-source-provenance`);
- artifact digest `sha256:67e65674c80aa483c1914ed9d3768f89bb95d9f57383382536a20b1de05ea2d4`;
- result: **SUCCESS**.

A valid/zero-finding provenance manifest is not a copyright certificate.

## SBOM / third-party boundary

Exact-tree CycloneDX build-SBOM evidence:

- workflow run `35255499669`;
- artifact ID `10512014953`;
- artifact `arvectum-proxy-launcher-sbom-1f4658c509a8b285461f212d0b9c5cbb08583a92`;
- artifact digest `sha256:eee846c8995cc1b5c17ad491774048831d87394f13011007637a29cd70360fef`;
- result: **SUCCESS**.

The repository SBOM is a build-dependency SBOM and must not be represented as a universal final-payload legal inventory.

AppImage remains **HOLD / excluded from the current clean-IP approval scope** until separately cleared.

## Existing private rights instrument

The executed 2026-09-14 private rights evidence remains the primary historical chain-of-title instrument:

`docs/evidence/APL_IP_001_V0_2_5_PRIVATE_RIGHTS_EVIDENCE_RECEIPT_2026-09-14.md`.

The public receipt identifies Arvectum Proxy Launcher rather than a replacement v0.2.9-only object. The repository therefore does not require a duplicate transfer merely because a version number changed.

However, repository metadata cannot decide whether the exact private wording also covers future results/modifications created after 2026-09-14. The current rights carry-forward note is:

`docs/legal/APL_IP_001_V0_2_9_RIGHTS_CARRY_FORWARD_NOTE_2026-09-18.md`.

## Human-authorship / legal boundary

The Owner supplied the actual 2026-09-14 instrument and current factual confirmations. For the current v0.2.9 filing-evidence packet:

- R-1A instrument review is complete;
- R-2 current Rospatent facts are confirmed;
- R-3 current corporate/Russian-control facts are confirmed;
- R-4 human creative-control / AI-as-tool / no-known-deliberate-copying facts are confirmed;
- current promoted platform scope is confirmed.

A separate question remains possible in legal theory for independently copyrightable human-authored contributions created after 2026-09-14. The project previously escalated that residual question into a mandatory two-party/future-rights agreement. The Owner rejected that process as unnecessary, and the project now treats such an instrument as **optional external legal hardening**, not as a blocker for the current APL-IP-001 engineering/filing-evidence objective.

This record does not decide the residual copyright question as a legal opinion. If an expert council, registry reviewer or external counsel specifically requires an additional chain-of-title instrument, address that request directly.

## Baseline verdict

- APL-IP-003 canonical-source engineering: **COMPLETE**.
- APL-IP-002 dependency/sovereignty inventory: **COMPLETE / release facts governed separately**.
- Exact v0.2.9 source/tag tree identity: **PASS**.
- Exact-tree provenance binding: **PASS**.
- Exact-tree build-SBOM binding: **PASS**.
- v0.2.5 -> v0.2.9 engineering drift reconciliation: **PASS / OWNER FACTUAL CARRY-FORWARD RECORDED**.
- Existing 2026-09-14 private rights evidence: **REVIEWED / OPERATIVE CURRENT CHAIN-OF-TITLE EVIDENCE**.
- AppImage promoted distribution: **HOLD / OUT OF CURRENT APPROVAL SCOPE**.
- R-1A/R-2/R-3/R-4 factual evidence: **COMPLETE / OWNER CONFIRMED**.
- R-1B future-rights instrument: **OPTIONAL EXTERNAL LEGAL HARDENING / NOT A CURRENT FILING BLOCKER**.
- Current project verdict: **FILING_EVIDENCE_COMPLETE_WITH_OPTIONAL_LEGAL_HARDENING**.
- Clean-IP/legal tag is not required for the current registry filing packet; do not manufacture one from automation. If a separate legal-baseline tag is ever desired, require a deliberately scoped human review.
- Clean IP baseline/tag: **BLOCKED** as a separate optional legal-baseline action until that deliberately scoped human/legal review occurs; this BLOCKED state does not block the current filing-evidence packet. A separate clean-IP baseline/tag may be created only after that optional review is **explicitly APPROVED** by the authorized human/legal reviewer.

**NO CLEAN-IP TAG IS AUTHORIZED BY AUTOMATION OR THIS RECORD.** Existing `v0.2.5` and `v0.2.9` tags must never be moved.
