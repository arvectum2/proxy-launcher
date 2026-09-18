# APL-IP-001 — v0.2.9 candidate reconciliation

Date: 2026-09-18  
Tracking: #57  
Verdict: **CONDITIONAL — ENGINEERING RECONCILED / HUMAN RIGHTS-CARRY-FORWARD GATE OPEN**

## 1. Why v0.2.9 is the current object

The prior current APL-IP-001 packet was bound to the immutable `v0.2.5` release on 2026-09-14. That release remains historical provenance and physical-acceptance evidence, but it is no longer the filing/current release object.

The Russian Software Register dossier and current public product line are now `v0.2.9`. A final human/legal decision must therefore be bound to the exact `v0.2.9` source tree and promoted release scope rather than silently reusing the `v0.2.5` disposition.

No `v0.2.5` tag, artifact or historical record is moved or rewritten by this reconciliation.

## 2. Exact accepted v0.2.9 identity

- accepted product-source commit: `ca7c1019e78cb3ee1e57173f2b58ecea0c27b919`;
- accepted product-source tree: `55f2d50f96387e5d55583ac90ca3d0b48f80ce99`;
- immutable release tag: `v0.2.9`;
- annotated tag object: `59dfd56191c8d9aa0e71a9fba2d86baaaf843520`;
- tag commit: `d13d9dac2ae2439c2fe70d32e1b168df320a9bd2`;
- tag-commit tree: `55f2d50f96387e5d55583ac90ca3d0b48f80ce99`.

The accepted PR head and the final tag commit therefore resolve to the **same exact source tree**. The final PR head contained checkpoint closeout after the accepted product bytes; the merge/tag commit preserves the same tree.

### Promoted release assets

GitHub release `v0.2.9` publishes:

- Windows portable ZIP SHA-256: `6f541b28c08834170258b48e27ffeafc6a0ad0e9c3a27760ec02cc7d01a305d0`;
- Windows Setup SHA-256: `a483c64205ad8a0d7a2e53e795714dd67d30c5c95f70f231d05a45b6f6db425c`;
- Astra Linux DEB SHA-256: `f1bdb58ed4dad02bcc391ae88c8102062a2ed75860f5735cbe45dd6569d77711`;
- RED OS RPM SHA-256: `59a3a45562da3c65691e901471bdaab16f0de94f5bbc4dfa786f524d417660fc`;
- `SHA256SUMS.txt` asset SHA-256: `20042bcc6e65fce39cdeb777ff4c6e06c91403034cbcd1eaf1bd9ecc9823bc38`.

These package digests identify the promoted `v0.2.9` release scope. They do not by themselves prove copyright ownership.

## 3. Engineering drift from v0.2.5 to v0.2.9

The repository comparison `v0.2.5..v0.2.9` is 135 commits ahead. Material product-source evolution is real, so a silent legal carry-forward is not permitted.

### v0.2.5 -> v0.2.6 — Astra/Linux product lane

Material runtime/platform changes include:

- `application_filesystem.py`;
- `backend_runtime.py`;
- `linux_backend.py`;
- `linux_desktop_proxy.py`;
- `linux_diagnostics.py`;
- `linux_gui.py`;
- `proxy_core.py`;
- Linux packaging/build/release code and related acceptance tooling.

Engineering classification: **Astra/Linux runtime, desktop-proxy, diagnostics and packaging expansion**.

### v0.2.6 -> v0.2.7 — RED OS/RPM lane

Material runtime/platform changes include:

- `backend_runtime.py`;
- `capability_model.py`;
- `linux_backend.py`;
- `linux_desktop_proxy.py`;
- `linux_gui.py`;
- `linux_runtime.py`;
- `proxy_core.py`;
- RPM packaging/build/release code.

Engineering classification: **RED OS/KDE/RPM platform expansion**.

### v0.2.7 -> v0.2.8 — Linux recovery hardening

Material runtime changes include:

- `linux_backend.py`;
- `linux_gui.py`;
- `linux_policykit_ux.py`;
- `proxy_core.py`.

Engineering classification: **mixed-state recovery / platform wording hardening**.

### v0.2.8 -> v0.2.9 — Windows rollback ownership symmetry

Material runtime changes include:

- `windows_system_proxy.py`;
- `proxy_core.py`;
- associated Windows regression tests and version metadata.

Engineering classification: **saved-or-Arvectum ownership validation and fail-closed rollback safety**.

No dependency-lock file changed across the `v0.2.5..v0.2.9` comparison. The third-party/build dependency boundary remains governed separately by SBOM, `THIRD_PARTY_NOTICES.txt` and APL-IP-002.

This classification is engineering provenance evidence, not a legal similarity opinion or proof of authorship.

## 4. Exact-tree provenance and SBOM evidence

The final PR head `ca7c1019...`, the pull-request synthetic merge `1f4658c509a8b285461f212d0b9c5cbb08583a92`, and the final tag commit `d13d9dac...` all resolve to the exact tree:

`55f2d50f96387e5d55583ac90ca3d0b48f80ce99`.

Therefore PR evidence generated from the synthetic merge is exact-tree evidence for the released source object.

### Source provenance

- workflow: `APL-IP-001 provenance`;
- run: `35255499712`;
- PR head: `ca7c1019e78cb3ee1e57173f2b58ecea0c27b919`;
- evidence checkout/synthetic merge: `1f4658c509a8b285461f212d0b9c5cbb08583a92`;
- exact tree: `55f2d50f96387e5d55583ac90ca3d0b48f80ce99`;
- artifact ID: `10511679846`;
- artifact: `apl-ip-001-source-provenance`;
- artifact digest: `sha256:67e65674c80aa483c1914ed9d3768f89bb95d9f57383382536a20b1de05ea2d4`;
- result: **SUCCESS**.

### CycloneDX build SBOM

- workflow: `SBOM`;
- run: `35255499669`;
- PR head: `ca7c1019e78cb3ee1e57173f2b58ecea0c27b919`;
- evidence checkout/synthetic merge: `1f4658c509a8b285461f212d0b9c5cbb08583a92`;
- exact tree: `55f2d50f96387e5d55583ac90ca3d0b48f80ce99`;
- artifact ID: `10512014953`;
- artifact: `arvectum-proxy-launcher-sbom-1f4658c509a8b285461f212d0b9c5cbb08583a92`;
- artifact archive digest: `sha256:eee846c8995cc1b5c17ad491774048831d87394f13011007637a29cd70360fef`;
- result: **SUCCESS**.

The repository SBOM is a build-dependency SBOM, not a universal binary/legal inventory.

## 5. Existing private rights instrument

The private evidence receipt dated 2026-09-14 remains valid historical evidence metadata and is not replaced:

`docs/evidence/APL_IP_001_V0_2_5_PRIVATE_RIGHTS_EVIDENCE_RECEIPT_2026-09-14.md`.

It records an executed sole-participant/rightsholder decision contributing the exclusive right in **Arvectum Proxy Launcher** to ООО «Арвектум» in full and records that the program was not then registered with Rospatent.

The public receipt does **not** establish by itself whether the exact private wording also disposes of future results/modifications created after 2026-09-14. That question is intentionally left to a human review of the executed instrument and the factual basis for post-2026-09-14 creative contributions.

This reconciliation therefore does **not** require a duplicate version-specific assignment merely because the release number changed, and it also does **not** fabricate a conclusion that all later creative contributions automatically belong to ООО «Арвектум».

## 6. Current human/legal gates

- **R-1A — EXECUTED BASIS RECORDED / HUMAN VERIFY:** inspect the actual 2026-09-14 instrument and confirm that the object is sufficiently identified as Arvectum Proxy Launcher and that the executed private evidence is authentic/current.
- **R-1B — HUMAN REQUIRED:** determine the rights basis for material creative contributions made after 2026-09-14 and included in the exact `v0.2.9` tree. This may be satisfied by the wording of the existing instrument if it validly covers future results, by a service/employment/corporate basis, by a separate assignment, or by another documented basis. Repository automation may not choose among these.
- **R-2 — HUMAN REQUIRED:** confirm current Rospatent status. The current repository record says the program is not registered and registration is not relied upon as the transfer basis.
- **R-3 — HUMAN REQUIRED:** confirm applicable corporate approval/exception basis and current corporate/Russian-control facts.
- **R-4 — HUMAN REQUIRED:** explicitly carry forward the factual human-authorship/creative-control statements to the material `v0.2.5 -> v0.2.9` changes and approved release scope.

## 7. Promoted approval scope

Candidate current approval scope:

- Windows x64 Setup;
- Windows x64 portable ZIP;
- Astra Linux x86-64 DEB;
- RED OS x86-64 RPM.

AppImage remains **HOLD / excluded** until separately cleared. macOS production distribution and mobile are not inferred into this approval.

## 8. Decision

Engineering reconciliation: **PASS**.  
Exact released source-tree identity: **PASS**.  
Exact-tree provenance/SBOM binding: **PASS**.  
Human/legal rights carry-forward: **PENDING**.  
Overall verdict: **CONDITIONAL_HUMAN_LEGAL_GATE**.

**NO CLEAN-IP TAG IS AUTHORIZED BY THIS RECORD.** A clean-IP/legal baseline may be created only after the current v0.2.9 human/legal sign-off is explicitly approved by an authorized human. Existing release tags remain immutable.
