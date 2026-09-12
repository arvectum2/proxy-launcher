# APL-REL-014 — exact signed-set lifecycle/recovery evidence

**Status:** IMPLEMENTED / REPOSITORY COMPLETE / 0.2.4 OWNER EVIDENCE MATERIALIZATION REQUIRED  
**Target release:** `0.2.4`  
**Owner:** ООО «Арвектум»

## 1. Goal

APL-REL-014 binds the exact Windows product bytes selected for publication to the already completed physical APL-WIN-014 lifecycle proof, then makes that proof part of the Russian signed release set itself.

The required chain is:

```text
immutable APL-WIN-014 acceptance bundle
  -> exact candidate_evidence.json from that bundle
  -> exact APL-WIN-014 physical PASS result
  -> exact Setup + portable release ZIP
  -> apl-rel-014-lifecycle-evidence.json
  -> REL-011 SHA256SUMS.txt + CryptoPro/Rutoken detached signature
  -> REL-012 verification
  -> REL-013 post-sign binding
  -> PUBLISH
```

A version label is never sufficient: every relevant boundary is SHA-256-bound.

## 2. Exact governed identities

Canonical contract:

```text
release/APL_REL_014_EXACT_SIGNED_SET_CONTRACT.json
```

The contract deliberately distinguishes the acceptance transport from the customer release artifact:

- candidate source commit: `e2278dbbd99b0d98ba9e4f836e40b2d60ea94b30`;
- immutable APL-WIN-014 acceptance bundle: `apl-win-014-final-0.2.4-34642663604-1.zip`;
- acceptance bundle SHA-256: `467864f286dc4c4de6c0f6033ae5cd5420a691c1bc9a32bf4891285c8c1d29bf`;
- exact `candidate_evidence.json` inside that bundle SHA-256: `3bba419d779b6e1ffd9a75c13596ce7099f812e854fc1c9531095951aadc1910`;
- **portable release ZIP** SHA-256: `e810a7912d8cc79fbf1c18629cd8feda97fed227b7b92aa01d1f56b241685f0c`;
- Setup SHA-256: `28eb0b06c2f478b46d5845c6bb1970c96e20a2f6fdaf1d48501ed69f52ea6965`;
- application EXE SHA-256: `0415226f882e16a0ce370b766c4c68d3c23861f97361da093a1fd9d9f0e0832c`;
- predecessor `0.2.3` Setup SHA-256: `5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414`;
- predecessor application SHA-256: `f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a`;
- required signer thumbprint: `EE1CFA955BA22F03C39C76B183D94CD37494582E`.

The `467864…` hash is the immutable acceptance/test-kit bundle accepted during APL-WIN-014. It is **not** the portable artifact that customers receive. The portable release artifact inside that bundle is `e810a791…`. Keeping both identities is intentional: the first anchors provenance of the physical acceptance inputs; the second anchors the signed publication set.

## 3. Authoritative physical evidence

The raw result must have schema:

```text
arvectum.proxy.apl-win-014-final-0.2.4-physical.v1
```

and must be the original output of:

```text
tools/apl_win_014_final_0_2_4_physical.ps1
```

APL-REL-014 requires `result = PASS`, exact source/Setup/application/predecessor identities, PASS for predecessor/upgrade/runtime/rollback/repair/uninstall, PASS for App Control before/after/3077, zero Arvectum-related Code Integrity 3077 blocks, PAC HTTP 200, the governed WinINET PAC URL and real listener/starter process IDs.

The raw physical JSON must be copied from the preserved dedicated acceptance stand. **Do not reconstruct or hand-author it from the Markdown closure summary.**

## 4. Binder

Canonical tool:

```text
tools/apl_rel_014_exact_evidence.py
```

In addition to validating the product and physical evidence, the binder now refuses any `candidate_evidence.json` whose own SHA-256 differs from the exact copy embedded in the immutable accepted bundle. This prevents a later JSON with matching top-level hashes from being substituted for the artifact actually accepted.

Example:

```powershell
py -3 .\tools\apl_rel_014_exact_evidence.py `
  --candidate-evidence "C:\Arvectum\Evidence\APL-REL-014\candidate_evidence.json" `
  --physical-result "C:\Arvectum\Evidence\APL-REL-014\apl-win-014-final-0.2.4-physical-result.json" `
  --release-directory "C:\Arvectum\Releases\0.2.4-final"
```

The only canonical output is:

```text
C:\Arvectum\Releases\0.2.4-final\apl-rel-014-lifecycle-evidence.json
```

inside the release directory. External/non-canonical output is rejected.

## 5. Signed-set design

`apl-rel-014-lifecycle-evidence.json` is created **before** REL-011. REL-011 therefore places it in `SHA256SUMS.txt` and `signing-evidence.json -> assets[]`, and the CryptoPro/Rutoken detached signature authenticates that evidence together with the exact Setup and portable release ZIP.

The generated evidence records the acceptance-bundle identity, exact source `candidate_evidence.json` hash, original raw physical-result hash, release asset hashes, lifecycle/App Control PASS state, runtime PAC/WinINET evidence, contract hash and required signer identity. It explicitly does **not** claim final signed-set PASS before REL-013.

## 6. REL-013 post-sign binding

`tools/russian_production_release_gate.ps1` fails closed unless the REL-014 JSON is a signed asset, its contract hash matches the clean release worktree, its Setup/portable/application/predecessor identities match the exact contract, all physical gates are PASS, REL-011 used the governed signer/mode, REL-012 verifies the complete signed set, the negative tamper test fails as expected, and Git provenance/worktree checks pass.

Only then may REL-013 emit:

```text
rel014_exact_lifecycle_evidence = PASS
rel014_signed_asset_binding = PASS
decision = PUBLISH
```

## 7. Required ceremony order

1. Export the original raw APL-WIN-014 physical-result JSON from `ARVECTUM-DEMO` without editing it.
2. Use the exact `candidate_evidence.json`, Setup and portable ZIP extracted from acceptance bundle SHA `467864…`.
3. Assemble the final release directory with Setup SHA `28eb…` and portable SHA `e810…`.
4. Prepare REL-012 consumer verification files.
5. Run the REL-014 binder and require PASS.
6. Confirm `apl-rel-014-lifecycle-evidence.json` is inside the final release directory.
7. Run owner-operated REL-011 CryptoPro/Rutoken signing; do not modify release files afterwards.
8. Run REL-012 and REL-013 against the exact signed directory and clean tagged release worktree.
9. Publish only on REL-013 `PUBLISH` with both REL-014 PASS fields.

## 8. Safety and fail-closed boundary

Publication is blocked for wrong/missing acceptance evidence, candidate-evidence substitution, wrong Setup/portable/application/predecessor bytes, incomplete physical lifecycle/App Control proof, Code Integrity blocks, wrong PAC/runtime evidence, wrong signer, signed-set drift, verification failure or provenance failure.

The historical owner-host APL-REL-014 incident remains authoritative. Destructive lifecycle acceptance is **not** repeated on an owner workstation. This task reuses the completed dedicated-host APL-WIN-014 physical PASS and binds it to the signed set.

## 9. Current completion state

Repository implementation is complete after CI/merge. The remaining non-fabricable owner operation is to copy the original raw physical-result JSON from the preserved acceptance stand, materialize the REL-014 JSON with the binder, and execute the real REL-011/REL-012/REL-013 ceremony with the hardware-backed key.

Until that original raw physical JSON is consumed and the real signing ceremony returns `PUBLISH`, `0.2.4` must not be described as a completed signed production release.
