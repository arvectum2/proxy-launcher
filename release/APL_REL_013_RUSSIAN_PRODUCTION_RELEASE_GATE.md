# APL-REL-013 — Russian production release gate

**Status:** IMPLEMENTED / REPOSITORY COMPLETE / MUST RUN FOR EVERY PRODUCTION RELEASE  
**Decision date:** 2026-08-16; APL-REL-014 binding added 2026-09-12  
**Primary market:** Russian Federation  
**Owner:** ООО «Арвектум»

## 1. Goal

APL-REL-013 turns the Russia-first release chain into a single fail-closed publication decision.

The preceding tasks established:

```text
APL-REL-010
  real Rutoken/CryptoPro hardware POC
  governed ООО «Арвектум» certificate
  release-evidence-only classification

APL-REL-011
  final assets -> SHA256SUMS.txt
  -> detached CryptoPro/Rutoken signature
  -> signer-certificate.cer
  -> signing-evidence.json

APL-REL-012
  end-user verifier
  -> asset SHA-256 verification
  -> detached CryptoPro verification
  -> governed signer binding
  -> Russian PASS/FAIL UX

APL-REL-014
  exact product set -> exact APL-WIN-014 lifecycle/recovery evidence
  -> apl-rel-014-lifecycle-evidence.json
  -> evidence file becomes a normal REL-011 signed asset
  -> exact Setup/portable/lifecycle identity is re-bound after signing
```

APL-REL-013 answers the final operational question:

> **Можно ли публиковать этот конкретный релиз?**

There are only two valid outcomes:

```text
PUBLISH
НЕ ПУБЛИКОВАТЬ
```

Any missing, inconsistent or unproven condition is `НЕ ПУБЛИКОВАТЬ`.

## 2. Canonical gate

```text
tools/russian_production_release_gate.ps1
```

The gate must run on Windows against the exact final directory that is intended for publication.

It does not build or sign a release. It is deliberately downstream of the owner-operated REL-011 ceremony and downstream of APL-REL-014 pre-sign evidence materialization.

## 3. Required input state

The final release directory must already contain at least:

```text
<exact product release asset(s)>
verify_russian_release.ps1
VERIFY_RUSSIAN_RELEASE.cmd
apl-rel-014-lifecycle-evidence.json
SHA256SUMS.txt
SHA256SUMS.txt.sig
signer-certificate.cer
signing-evidence.json
```

Both the verifier UX and `apl-rel-014-lifecycle-evidence.json` must have been placed in the directory **before** REL-011 signing, so all three are themselves covered by the signed manifest.

For the current `0.2.4` release, APL-REL-014 additionally binds the release to:

```text
release/APL_REL_014_EXACT_SIGNED_SET_CONTRACT.json
```

The contract pins the immutable APL-WIN-014-accepted source commit and exact Setup, portable ZIP, application and predecessor identities.

## 4. What the gate proves

APL-REL-013 fails closed unless all of the following are true:

1. The run is on Windows.
2. The supplied `Version`, `GitTag` and `GitCommit` are mutually consistent.
3. `signing-evidence.json` identifies `Arvectum Proxy Launcher`.
4. The evidence was produced by `APL-REL-011` in `russian-qualified-evidence` mode.
5. Evidence version/tag/commit exactly match the requested production release.
6. REL-011 records successful detached-signature verification.
7. Evidence does not report PIN storage or private-key export attempts.
8. The signer thumbprint is the currently governed ООО «Арвектум» release-evidence certificate:

```text
EE1CFA955BA22F03C39C76B183D94CD37494582E
```

9. The signer subject identifies `АРВЕКТУМ`.
10. `apl-rel-014-lifecycle-evidence.json` has the canonical APL-REL-014 schema, product, version, `PASS` result and pre-sign scope.
11. The REL-014 evidence records the exact repository contract SHA-256 used to produce it, and that hash matches the contract in the current release worktree.
12. The REL-014 candidate source commit, Setup, portable ZIP, application and predecessor hashes match the exact-set contract.
13. Every required lifecycle gate is PASS: predecessor, upgrade, runtime, rollback, repair and uninstall.
14. App Control before/after and Code Integrity 3077 gates are PASS, with `3077` count exactly `0`.
15. The recorded runtime has PAC HTTP `200` and the governed WinINET `AutoConfigURL`.
16. REL-014 requires the same signing mode and governed signer identity actually used by REL-011.
17. The REL-014 JSON itself appears exactly once in REL-011 `assets[]` with its real SHA-256.
18. The exact Setup and portable ZIP appear exactly once in REL-011 `assets[]` with the same hashes proven by REL-014.
19. The complete untouched final release directory passes the bundled REL-012 verifier, cryptographically authenticating the manifest that covers the REL-014 evidence and product assets.
20. The current Git `HEAD` is exactly the release commit.
21. The requested Git tag resolves exactly to that commit.
22. The release commit is an ancestor of canonical local `main`.
23. The Git worktree is clean.
24. A disposable copy of the release is modified and the bundled REL-012 verifier rejects it.
25. No ungoverned Authenticode/SmartScreen claim is promoted by the gate.

Only after all checks pass may the gate emit `PUBLISH`.

## 5. Mandatory negative tamper test

A positive verifier result alone is not enough for the production gate.

APL-REL-013 copies the exact final release to a temporary directory, changes one signed asset and executes the **bundled** `verify_russian_release.ps1` against that tampered copy.

Expected result:

```text
REL-012 original exact final set: PASS
REL-012 tampered disposable copy: FAIL
APL-REL-013 interpretation: PASS
```

If the tampered copy is accepted, the production decision is automatically:

```text
НЕ ПУБЛИКОВАТЬ
```

The original release directory is never modified by this test.

## 6. Git provenance boundary

The production package must be traceable to one exact approved repository state.

The gate requires:

```text
HEAD == GitCommit
GitTag^{commit} == GitCommit
GitCommit is ancestor of main
worktree == clean
```

The same clean worktree contains the APL-REL-014 exact-set contract whose SHA-256 must match the contract hash recorded inside the signed lifecycle evidence.

This prevents a production release from being approved from an uncommitted local patch, the wrong tag, a branch state not represented by canonical `main`, or an evidence file generated from a different release contract.

## 7. Publication-decision evidence

After PASS, the gate writes a non-secret machine-readable decision file named by default:

```text
<release-directory-name>.production-release-gate.json
```

It is deliberately written **outside** the signed release directory.

Putting it inside the final directory after REL-011 signing would add an unlisted file and invalidate REL-012 verification. The gate explicitly rejects an output path inside the signed release set.

The decision record contains, among other fields:

```text
task = APL-REL-013
decision = PUBLISH
version / git_tag / git_commit
signer identity
REL-011 detached-signature status
REL-012 exact-release PASS
REL-012 negative-tamper expected FAIL
rel014_exact_lifecycle_evidence = PASS
rel014_signed_asset_binding = PASS
rel014_candidate_source_commit
rel014_evidence_sha256
rel014_setup_sha256
rel014_portable_sha256
rel014_application_sha256
git/tag/main/worktree checks
explicit false values for Authenticode/SmartScreen claims
```

This JSON is release-operation evidence, not a new cryptographic trust anchor. The cryptographic trust anchor remains the REL-011 signed manifest and governed signer identity.

## 8. Canonical owner-operated sequence

For the current `0.2.4` release, follow the exact APL-REL-014 runbook in:

```text
release/APL_REL_014_EXACT_SIGNED_SET_LIFECYCLE_RECOVERY_EVIDENCE.md
```

For **каждого релиза** whose exact-set lifecycle contract requires APL-REL-014 binding, the sequence is:

```powershell
# 1. Build/assemble the exact final product assets proven by the release contract.

# 2. Add the consumer verifier before signing.
powershell -ExecutionPolicy Bypass -File .\tools\prepare_russian_release_verification_ux.ps1 `
  -ReleaseDirectory "C:\release\Arvectum-Proxy-Launcher-0.2.4"

# 3. Materialize APL-REL-014 evidence INSIDE the release directory, before signing.
py -3 .\tools\apl_rel_014_exact_evidence.py `
  --candidate-evidence "<preserved-candidate-evidence.json>" `
  --physical-result "<preserved-physical-result.json>" `
  --release-directory "C:\release\Arvectum-Proxy-Launcher-0.2.4"

# 4. Run REL-011 owner-operated Rutoken/CryptoPro signing.
powershell -ExecutionPolicy Bypass -File .\tools\russian_signed_release.ps1 `
  -ReleaseDirectory "C:\release\Arvectum-Proxy-Launcher-0.2.4" `
  -Version "0.2.4" `
  -GitTag "<authorized-v0.2.4-tag>" `
  -GitCommit "<40-character-authorized-release-commit>" `
  -CertificateThumbprint "EE1CFA955BA22F03C39C76B183D94CD37494582E"

# 5. Run the final production gate.
powershell -ExecutionPolicy Bypass -File .\tools\russian_production_release_gate.ps1 `
  -ReleaseDirectory "C:\release\Arvectum-Proxy-Launcher-0.2.4" `
  -Version "0.2.4" `
  -GitTag "<authorized-v0.2.4-tag>" `
  -GitCommit "<40-character-authorized-release-commit>"
```

Do not add or modify files inside the release directory after REL-011 signing.

Publication is permitted only if the final command prints:

```text
APL-REL-013 Russian production release gate: PASS
Publication decision: PUBLISH
REL-012 exact final set verification: PASS
APL-REL-014 exact lifecycle evidence signed-set binding: PASS
Negative tamper test: PASS (tampered copy correctly rejected)
```

## 9. Mandatory НЕ ПУБЛИКОВАТЬ conditions

Do not publish if any of these conditions is true:

- APL-REL-014 lifecycle evidence is absent, malformed or not PASS;
- the signed APL-REL-014 evidence was generated from a different exact-set contract;
- candidate source commit, Setup, portable ZIP, application or predecessor identity differs from the contract;
- any required lifecycle/App Control gate is not PASS or Code Integrity 3077 count is non-zero;
- the REL-014 evidence JSON itself is not covered by REL-011 signing evidence;
- the signed Setup or portable ZIP differs from the hashes proven by REL-014;
- REL-011 owner-operated signing did not complete successfully;
- REL-012 verification fails on the exact final download set;
- a signed asset is missing, changed or extra;
- the manifest, detached signature or exported certificate is inconsistent;
- the signer is not the governed Arvectum certificate;
- version/tag/commit metadata disagree;
- the local tag points to another commit;
- HEAD differs from the release commit;
- the release commit is not represented by canonical `main`;
- the worktree contains uncommitted changes;
- the negative tamper copy unexpectedly verifies successfully;
- evidence reports PIN storage or a private-key export attempt;
- release notes claim Authenticode, SmartScreen or Windows trusted-publisher status that has not been separately proven.

## 10. Authenticode / SmartScreen boundary

The current governed certificate proved by APL-REL-010 has no Code Signing EKU and remains classified:

```text
RELEASE-EVIDENCE-ONLY
```

Therefore APL-REL-013 does **not** claim:

```text
Authenticode signed
SmartScreen trusted
Windows trusted publisher
Microsoft trusted
ОТУЦ code-signed
```

A Russian release may be cryptographically verifiable and permitted for publication by this gate without possessing those separate OS-native trust properties.

## 11. CI boundary

Workflow:

```text
.github/workflows/russian-production-release-gate.yml
```

CI validates only the repository contract, APL-REL-014 binding rules and PowerShell syntax. It deliberately has:

- no Rutoken;
- no CryptoPro production identity;
- no certificate private key;
- no PIN;
- no production signing secret;
- no ability to manufacture the preserved APL-WIN-014 physical result.

CI cannot issue `PUBLISH` for a real production release. Only the owner-operated Windows ceremony against the exact final release set can do that.

## 12. Acceptance checklist

Repository implementation:

- [x] Fail-closed production gate implemented.
- [x] REL-011 evidence chain required.
- [x] REL-012 exact-final-set verification required.
- [x] Governed Arvectum signer pinned.
- [x] APL-REL-014 exact-set contract hash required.
- [x] Signed APL-REL-014 lifecycle evidence required.
- [x] Signed Setup/portable identities cross-bound to APL-REL-014.
- [x] Required lifecycle/App Control/3077 evidence checked fail-closed.
- [x] Version/tag/commit binding implemented.
- [x] Exact HEAD and tag target enforced.
- [x] Canonical `main` ancestry enforced.
- [x] Clean worktree enforced.
- [x] Mandatory disposable negative tamper test implemented.
- [x] Decision evidence kept outside signed release directory.
- [x] Authenticode/SmartScreen overclaiming prevented.
- [x] Non-secret CI contract and PowerShell syntax validation defined.

Per-release owner operation for `0.2.4`:

- [ ] Export/preserve the original accepted `candidate_evidence.json`.
- [ ] Export/preserve the authoritative raw APL-WIN-014 physical result.
- [ ] Assemble the exact contract-pinned Setup + portable set.
- [ ] Bundle REL-012 UX before signing.
- [ ] Run APL-REL-014 binder and create canonical lifecycle evidence inside the release directory.
- [ ] Run REL-011 with physical Rutoken/CryptoPro and receive PASS.
- [ ] Create/resolve the exact authorized release tag to the exact release commit.
- [ ] Run APL-REL-013 against the exact final signed download set.
- [ ] Receive `rel014_exact_lifecycle_evidence = PASS` and `rel014_signed_asset_binding = PASS` in decision evidence.
- [ ] Receive `Publication decision: PUBLISH`.
- [ ] Preserve the external `production-release-gate.json` with release records.
- [ ] Publish only that exact verified release set.

## 13. Completion definition

APL-REL-013 repository implementation remains complete when the gate script, contract tests, documentation and CI syntax checks are merged to `main`.

APL-REL-014 repository implementation is complete when its exact-set contract, evidence binder, regression tests, documentation and REL-013 post-sign binding are merged to `main`.

A specific product version becomes a **production-approved Russian release** only after its own real owner-operated APL-REL-014 + REL-011 + REL-012 + REL-013 ceremony returns PASS. Repository code cannot substitute for the preserved physical evidence or hardware signing ceremony.