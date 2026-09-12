# APL-REL-015 — 0.2.5 CFA hotfix exact release evidence

**Status:** IMPLEMENTED / REPOSITORY BINDING READY / OWNER-OPERATED SIGNING CEREMONY REQUIRED  
**Target release:** `0.2.5`  
**Owner:** ООО «Арвектум»

## Goal

APL-REL-015 is the release-specific evidence profile for the `0.2.5` Controlled Folder Access hotfix. It does not replace or rewrite the historical `0.2.4` APL-REL-014 contract. Instead it binds the exact `0.2.5` Setup and exact application bytes that passed real CFA/reboot acceptance to a customer portable package containing those same application bytes, then feeds that exact set into the existing Russia-first REL-011 -> REL-012 -> REL-013 chain.

The required chain is:

```text
0.2.5 accepted source commit
  -> exact Windows-installer CI run / exact Setup / exact application
  -> raw owner-host CFA + reboot + real HTTPS-through-proxy PASS
  -> portable materialized around the exact accepted application bytes
  -> apl-rel-015-cfa-hotfix-evidence.json
  -> REL-011 SHA256SUMS.txt + CryptoPro/Rutoken detached signature
  -> REL-012 verification
  -> REL-013/015 post-sign binding + negative tamper test
  -> PUBLISH
```

A matching version label or source commit is not enough. PyInstaller one-file output is not assumed byte-reproducible, so all product boundaries are SHA-256-bound.

## Exact accepted product identities

Canonical contract:

```text
release/APL_REL_015_0_2_5_CFA_HOTFIX_CONTRACT.json
```

The physically accepted identities are:

- accepted product source commit: `9e8ca7e851563082cd7d03d7543ccb360a37ec27`;
- Windows-installer GitHub Actions run: `34720855917`;
- installer artifact ID: `10306540886`;
- installer artifact ZIP SHA-256: `a9c973b68bfd58ff7c16afedb0d13edf98173ab0d690e189580e6f45327362ec`;
- exact Setup SHA-256: `9b5368d67874b7164ee56a245c75db4b23af593a1d72f7e947774516abcc95e3`;
- exact application SHA-256: `1ab36b7a6a0a225dcf06fb2c630d0d2ba47ec17578dbd5949f08e992853d653c`;
- raw final physical-reboot evidence SHA-256: `2afe6af76a69dc4d0b6869385dda6c4467c3d01e38997a04ca554c28aa24021a`.

The installer CI evidence records issue #171/CFA-safe handover PASS, full Windows RC fresh/upgrade/repair/uninstall PASS, configuration preservation, foreign-startup preservation and Gate R6 acceptance for those exact Setup/application identities.

## Authoritative physical acceptance

The original raw owner-host result is preserved byte-for-byte in repository evidence as:

```text
docs/evidence/APL_0_2_5_FINAL_PHYSICAL_REBOOT_2026-09-13.json
```

Its original SHA-256 is `2afe6af76a69dc4d0b6869385dda6c4467c3d01e38997a04ca554c28aa24021a` and schema is:

```text
arvectum.proxy.0.2.5.final-physical-reboot.v1
```

The evidence records `result = PASS` and proves after a clean reboot:

- application version `0.2.5` at the canonical `%LOCALAPPDATA%\Programs\ArvectumProxyLauncher` path;
- application SHA-256 exactly `1ab36b7a...653c`;
- canonical HKCU Run command with `--start`;
- exactly one PAC listener and canonical application ownership of port `8082`;
- PAC HTTP `200` at `http://127.0.0.1:8082/proxy.pac`;
- real HTTPS HTTP `200` to `https://example.com/` through local HTTP proxy `http://127.0.0.1:8080`;
- no legacy Python proxy runtime after the clean reboot.

This physical profile is intentionally about the `0.2.5` regression that escaped `0.2.4`: CFA-safe install/handover, stable canonical location, autostart and real post-reboot proxy continuity.

## Why the portable ZIP is materialized, not rebuilt

The Windows-installer run that produced the physically accepted Setup/application recorded a same-run portable ZIP SHA-256 of:

```text
7e65d980b376977b33263a7b7ad97ade9c3c83f3eb685c5ab624ce342fb71af0
```

but that ZIP itself was not retained in the installer artifact. A later Windows P0 portable build from the same source commit produced application SHA-256:

```text
fd253a86eeb64df602afaa99d45a4dea9899d7e556d348c67f55b0b59c08f91b
```

which differs from the physically accepted application `1ab36b7a...653c`. The later build therefore cannot silently replace the accepted product merely because the source commit and version match.

APL-REL-015 uses:

```text
tools/materialize_0_2_5_accepted_portable.ps1
```

This script performs packaging only. It:

1. requires the exact accepted application SHA-256 `1ab36b7a...653c`;
2. requires the exact same-source portable-template ZIP and pinned non-executable member hashes;
3. verifies that the template executable is the known later non-accepted build and never promotes it;
4. replaces only that template executable with the exact physically accepted application;
5. regenerates the internal portable `SHA256SUMS.txt` for the accepted application;
6. creates and reopens the final customer portable ZIP;
7. verifies every member, every pinned static hash and the exact accepted application identity;
8. refuses to overwrite an existing release output.

The resulting portable ZIP gets a new SHA-256 at materialization time. That hash is not guessed in advance: the APL-REL-015 binder records it, REL-011 includes it in the qualified-signed manifest, and the final REL-013/015 gate re-binds it to the signed set.

## Native runtime/toolchain regression baseline

`0.2.4` completed the broader dedicated APL-WIN-014 App Control physical gate for the PyInstaller native runtime. The `0.2.5` source retained the same pinned build Python `3.12.10` and PyInstaller `6.22.0` toolchain inputs.

APL-REL-015 carries that forward only as a **native-runtime/toolchain regression baseline**. It does not claim that the `0.2.5` executable is byte-identical to `0.2.4`, nor does it manufacture new Code Integrity evidence for a host on which that exact gate was not rerun. The exact `0.2.5` bytes are independently bound by current CI plus the CFA/reboot/real-connectivity physical acceptance above.

## Exact evidence binder

Canonical tool:

```text
tools/apl_rel_015_0_2_5_exact_evidence.py
```

It consumes:

- the preserved Windows-installer artifact directory from run `34720855917`;
- the original raw physical-result JSON;
- the exact physically accepted installed application;
- the final release directory containing the exact Setup and newly materialized portable ZIP;
- the repository contract.

It fails closed unless the exact evidence hashes and schemas match the contract, all required CI/CFA/lifecycle checks are PASS, the raw physical evidence is byte-exact, the portable contains the exact accepted application, all portable static members match the governed template, and the pinned runtime/toolchain regression baseline remains unchanged.

The only canonical pre-sign output is:

```text
apl-rel-015-cfa-hotfix-evidence.json
```

inside the release directory.

## Russia-first signed release chain

After APL-REL-015 creates the exact pre-sign evidence:

1. add the REL-012 consumer verification UX to the release directory;
2. run `tools/russian_signed_release.ps1` with the governed ООО «Арвектум» Rutoken/CryptoPro certificate;
3. require detached CryptoPro verification PASS;
4. run the bundled REL-012 verifier over the exact final signed directory;
5. run `tools/russian_production_release_gate_0_2_5.ps1`;
6. require exact Git/tag/main/clean-worktree provenance;
7. require APL-REL-015 evidence, Setup and portable ZIP each to be present exactly once in REL-011 `assets[]` with their exact hashes;
8. require the mandatory disposable tamper copy to fail REL-012 verification;
9. publish only if the final gate emits `Publication decision: PUBLISH`.

The governed signer remains:

```text
EE1CFA955BA22F03C39C76B183D94CD37494582E
```

The current certificate remains classified `RELEASE-EVIDENCE-ONLY`. The release may state that its SHA-256 manifest is qualified-signed by ООО «Арвектум» using CryptoPro/Rutoken. It must not claim Authenticode, SmartScreen, Microsoft trusted-publisher or ОТУЦ code-signing trust.

## Development-host legacy boundary

The acceptance host contained a historical development Run command using `P0_2_RECOVERY\Python312\pythonw.exe`. Production ownership code intentionally refused to overwrite that arbitrary Python command because it could not prove ownership under the strict installed-EXE command contract. On this known development host only, the operator migrated that value after exact validation.

The product ownership rule is not relaxed by APL-REL-015. Arbitrary Python commands remain foreign/unowned and must not be silently rewritten in customer environments.

## Completion definition

Repository implementation is complete when the APL-REL-015 contract, exact raw physical evidence, portable materializer, evidence binder, `0.2.5` production-gate profile, tests and CI syntax/contract checks are merged to canonical `main`.

The `0.2.5` product becomes a production-approved Russian release only after the real owner-operated ceremony produces:

```text
APL_REL_015_RESULT=PASS
APL_REL_012_RESULT=PASS
APL-REL-013/015 Russian production release gate: PASS
Publication decision: PUBLISH
```

and only that exact signed release set may then be published.