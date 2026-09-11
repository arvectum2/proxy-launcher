# APL-REL-014 — exact signed-set lifecycle/recovery evidence

**Status:** IMPLEMENTED / REPOSITORY COMPLETE / 0.2.4 OWNER EVIDENCE MATERIALIZATION REQUIRED  
**Target release:** `0.2.4`  
**Owner:** ООО «Арвектум»

## 1. Goal

APL-REL-014 binds the exact Windows product bytes selected for release to the already completed real APL-WIN-014 lifecycle proof and then makes that lifecycle proof part of the Russian signed release set itself.

The gate must prove one continuous chain:

```text
immutable 0.2.4 candidate
  -> exact candidate_evidence.json
  -> exact APL-WIN-014 physical PASS result
  -> exact Setup + portable ZIP selected for publication
  -> apl-rel-014-lifecycle-evidence.json
  -> REL-011 SHA256SUMS.txt
  -> detached CryptoPro/Rutoken signature
  -> REL-012 exact-set verification
  -> REL-013 signed-set binding
  -> PUBLISH
```

A documentation statement that the same version was tested is not enough. The hashes must match at every boundary.

## 2. Exact governed 0.2.4 identity

Canonical contract:

```text
release/APL_REL_014_EXACT_SIGNED_SET_CONTRACT.json
```

It pins:

- candidate source commit: `e2278dbbd99b0d98ba9e4f836e40b2d60ea94b30`;
- portable ZIP SHA-256: `467864f286dc4c4de6c0f6033ae5cd5420a691c1bc9a32bf4891285c8c1d29bf`;
- Setup SHA-256: `28eb0b06c2f478b46d5845c6bb1970c96e20a2f6fdaf1d48501ed69f52ea6965`;
- application EXE SHA-256: `0415226f882e16a0ce370b766c4c68d3c23861f97361da093a1fd9d9f0e0832c`;
- predecessor `0.2.3` Setup SHA-256: `5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414`;
- predecessor application SHA-256: `f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a`;
- required PAC URL: `http://127.0.0.1:8082/proxy.pac`;
- required signer thumbprint: `EE1CFA955BA22F03C39C76B183D94CD37494582E`.

Changing any governed identity requires an explicit new release contract. It must never be silently accepted by passing a different path or JSON file.

## 3. Authoritative physical source

The accepted physical result was produced by:

```text
tools/apl_win_014_final_0_2_4_physical.ps1
```

Expected schema:

```text
arvectum.proxy.apl-win-014-final-0.2.4-physical.v1
```

APL-REL-014 requires all of the following from the raw physical result:

- `result = PASS`;
- exact candidate source commit;
- exact candidate Setup hash;
- exact candidate application hash;
- exact predecessor Setup hash;
- predecessor PASS;
- real upgrade `0.2.3 -> 0.2.4` PASS;
- runtime PASS;
- rollback PASS;
- repair PASS;
- uninstall PASS;
- App Control before PASS;
- App Control after PASS;
- Code Integrity 3077 PASS with count `0`;
- PAC HTTP `200`;
- non-trivial PAC body;
- exact WinINET `AutoConfigURL`;
- real listener/starter process IDs;
- no block reason.

The authoritative raw file remains on the dedicated acceptance stand at the path recorded by the APL-WIN-014 closure evidence. Do not reconstruct or hand-author this raw result from the Markdown summary.

## 4. Evidence binder

Canonical tool:

```text
tools/apl_rel_014_exact_evidence.py
```

The tool accepts only non-secret evidence and release files. It does not accept a PIN, password, PFX, private key, certificate store mutation or signing secret.

Example for the current release ceremony:

```powershell
py -3 .\tools\apl_rel_014_exact_evidence.py `
  --candidate-evidence "C:\Arvectum\Evidence\APL-REL-014\candidate_evidence.json" `
  --physical-result "C:\Arvectum\Evidence\APL-REL-014\apl-win-014-final-0.2.4-physical-result.json" `
  --release-directory "C:\Arvectum\Releases\0.2.4-final"
```

The default output is deliberately fixed to:

```text
C:\Arvectum\Releases\0.2.4-final\apl-rel-014-lifecycle-evidence.json
```

A non-canonical filename or an output outside the final release directory is rejected.

## 5. Why the REL-014 JSON is inside the release set

`apl-rel-014-lifecycle-evidence.json` is created **before** REL-011 signing.

That is intentional. It becomes a normal release asset and therefore must appear in:

```text
SHA256SUMS.txt
signing-evidence.json -> assets[]
```

The detached CryptoPro/Rutoken signature over `SHA256SUMS.txt` consequently authenticates the lifecycle evidence file together with the exact product bytes.

This avoids a weak design where an unsigned external JSON could later be swapped independently of the signed release.

## 6. What the generated evidence records

The canonical schema is:

```text
arvectum.proxy.apl-rel-014-exact-evidence.v1
```

It records:

- `result = PASS` only after all exact checks succeed;
- version `0.2.4`;
- accepted candidate source commit;
- exact Setup filename/hash/size;
- exact portable ZIP filename/hash/size;
- exact application hash proven by the lifecycle;
- exact predecessor identities;
- every lifecycle/App Control gate as PASS;
- runtime PAC/WinINET evidence;
- SHA-256 of the repository exact-set contract;
- SHA-256 of the original `candidate_evidence.json`;
- SHA-256 of the original raw physical result;
- required REL-011 signing mode and signer identity;
- an explicit statement that final signed-set PASS is **not** claimed before REL-013.

## 7. Post-sign binding in APL-REL-013

`tools/russian_production_release_gate.ps1` now fails closed unless:

1. `apl-rel-014-lifecycle-evidence.json` exists in the final release directory;
2. it has the canonical schema/task/result/scope;
3. its contract hash matches the exact contract in the clean tagged release worktree;
4. its candidate source commit matches the contract;
5. its Setup/portable/application hashes match the contract;
6. its predecessor hashes match the contract;
7. all lifecycle/App Control gates remain PASS and Code Integrity 3077 count is zero;
8. the signer identity/mode requested by REL-014 matches REL-011;
9. the REL-014 JSON itself appears exactly once in REL-011 `assets[]` with its actual SHA-256;
10. the exact Setup and portable ZIP appear exactly once in REL-011 `assets[]` with the same hashes REL-014 proved;
11. REL-012 successfully verifies the complete signed set and detached signature;
12. the mandatory negative tamper test fails as expected;
13. normal REL-013 Git provenance and clean-worktree requirements also PASS.

Only then does the production decision include:

```text
rel014_exact_lifecycle_evidence = PASS
rel014_signed_asset_binding = PASS
```

and allow `decision = PUBLISH`.

## 8. Required ceremony order for 0.2.4

Use this order. Do not sign first and add REL-014 evidence afterwards.

1. Preserve/export the exact raw APL-WIN-014 physical result from `ARVECTUM-DEMO` without editing it.
2. Preserve/export the exact `candidate_evidence.json` from the accepted final candidate kit.
3. Assemble the final release directory with the exact governed Setup and portable ZIP.
4. Run the REL-012 verification-UX preparation helper so the consumer verifier files are already present.
5. Run `apl_rel_014_exact_evidence.py`; require PASS.
6. Confirm `apl-rel-014-lifecycle-evidence.json` is now inside the release directory.
7. Run REL-011 owner-operated CryptoPro/Rutoken signing. Do not modify release files afterwards.
8. Run REL-013 against the exact signed directory and clean tagged release worktree.
9. Publish only if REL-013 emits `PUBLISH` with both REL-014 fields set to PASS.

## 9. Fail-closed cases

APL-REL-014 or REL-013 must block publication for any of these conditions:

- wrong candidate commit;
- wrong Setup, portable ZIP or application hash;
- wrong predecessor identity;
- missing/raw malformed physical result;
- physical result not PASS;
- any lifecycle phase not PASS;
- App Control before/after not PASS;
- any Arvectum-related Code Integrity 3077 block;
- wrong PAC URL/status/runtime evidence;
- changed exact-set contract;
- REL-014 evidence omitted from the signed manifest;
- REL-014 evidence changed after signing;
- signed Setup/ZIP differs from the lifecycle-proven set;
- wrong signer identity or signing mode;
- REL-012 verification failure;
- negative tamper test unexpectedly succeeding.

## 10. Safety boundary

The 2026-08-20 owner-host APL-REL-014 incident remains authoritative historical evidence. Destructive lifecycle acceptance must not be rerun on a normal owner workstation.

This implementation **reuses** the already completed dedicated-host APL-WIN-014 physical PASS and binds its exact bytes into the release ceremony. It does not weaken Windows App Control and does not repeat a destructive owner-host migration test.

## 11. Current completion state

Repository implementation is complete when this change is merged and CI passes.

The current `0.2.4` per-release ceremony still requires one owner operation that GitHub cannot fabricate: export/copy the original raw `candidate_evidence.json` and `apl-win-014-final-0.2.4-physical-result.json` from the preserved acceptance material, run the binder against the exact final release directory, then execute REL-011/REL-013.

Until that real evidence file is materialized and signed, do **not** describe the public `0.2.4` signed-set ceremony as complete and do not publish a stable release solely from repository implementation status.
