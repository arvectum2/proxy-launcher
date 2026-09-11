# APL-WIN-014 final 0.2.4 physical acceptance

Status: **READY FOR ONE FINAL ARVECTUM-DEMO PHYSICAL EXECUTION AFTER EXACT 0.2.3 PREDECESSOR PRE-PROVISIONING**

This runbook is the canonical final physical procedure for APL-WIN-014. It replaces the historical 0.2.2/0.2.3 final-stand sequence. The product candidate is **0.2.4** and is produced once by `.github/workflows/apl-win-014-final-0-2-4.yml`; the same sealed bytes are used by CI and by the physical stand.

The dedicated/isolated Windows 11 host is `ARVECTUM-DEMO`. Its canonical base App Control policy is `dc1c604c-46ea-40b7-9f47-cf582b225d5e`. The base policy must remain **Enforced**, on disk, authorized, and configured with **Enabled:Allow Supplemental Policies**. Never switch it to Audit mode and never disable Smart App Control, App Control for Business, Defender, script enforcement, or another Windows protection to make a gate pass.

CryptoPro/Rutoken is not required for this final endpoint acceptance. Russian release signing is an upstream release-control concern; the remaining gate is exact-byte Windows lifecycle behavior under enforced App Control.

## Important legacy boundary

The sealed 0.2.3 predecessor predates the PowerShell/WDAC hardening added to the 0.2.4 installer. Its embedded maintenance path launches legacy PowerShell with `-File` and is therefore **not itself an acceptance target under the current enforced App Control/ConstrainedLanguage stand**.

For the final 0.2.4 acceptance, an **exact already-installed 0.2.3 predecessor state is a precondition**. Do not use the runner's historical fallback that invokes the 0.2.3 Setup when the install root is absent. Do not weaken App Control to make the legacy installer work.

The final physical proof begins only after the exact predecessor state has been provisioned from canonical sealed 0.2.3 release material and independently verified. The 0.2.4 runner then verifies that exact state again before performing the real `0.2.3 -> 0.2.4` upgrade.

## Candidate-derived Inno runtime boundary

The Inno loader child executable materialized as `setup.tmp` is part of the executable trust surface. Its bytes are **not assumed to be invariant merely because the compiler version is Inno Setup 6.7.1**.

The final workflow statically derives the exact child runtime from the exact candidate Setup with `tools/bootstrap/apl-win-014/extract_inno_6_7_1_runtime.py`, seals those bytes inside `policy-material`, records their SHA-256 and source Setup SHA-256 in both candidate evidence and the physical contract, and includes the derivation evidence in the same immutable final ZIP. The supplemental policy must authorize that candidate-derived runtime, not a historical runtime from a different Setup build.

## Inputs

Use exactly these inputs:

- the single ZIP artifact from workflow **APL-WIN-014 final 0.2.4**;
- canonical sealed predecessor material in `C:\Arvectum\Releases\0.2.3-russian-production`;
- canonical 0.2.3 Setup SHA-256 `5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414`;
- canonical installed 0.2.3 application SHA-256 `f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a`;
- candidate-derived Inno Setup 6.7.1 child runtime sealed inside the same candidate ZIP at the relative path recorded as `inno_runtime_filename` in `physical_test_contract.json`;
- Windows ConfigCI cmdlets and `CiTool.exe`.

Extract the workflow ZIP into a new immutable candidate directory. Do not edit, rebuild, rename, or substitute files inside it. `candidate_evidence.json`, `physical_test_contract.json`, the candidate-derived runtime/evidence, and `SHA256SUMS.txt` are the sealed identity contract.

## Phase 0 — exact predecessor precondition

Before the acceptance window, provision the canonical 0.2.3 installed state from sealed release material **without disabling or weakening App Control**.

Before continuing, the following must all be true:

- install root is `C:\Users\ARVECTUM-DEMO\Documents\ArvectumProxyLauncher`;
- `Arvectum Proxy Launcher.exe` SHA-256 is exactly `f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a`;
- cached `Arvectum Proxy Launcher Repair.exe` SHA-256 is exactly the canonical 0.2.3 Setup SHA-256 `5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414`;
- `build_manifest.json` records version `0.2.3` and the same application SHA-256;
- the per-user uninstall registration exists under `HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{6A5A0706-4015-4EAF-BFA1-25EF435C9E1B}_is1` with `DisplayVersion = 0.2.3`;
- `unins000.exe` and its data are present as part of the exact predecessor installation state.

If any item is absent or differs, stop. Do not synthesize a PASS and do not use a modified predecessor binary.

## Phase A — author the exact 0.2.4 supplemental policy

Run elevated Windows PowerShell 5.1. On an App Control host the interactive shell may be `ConstrainedLanguage` and the local execution policy may reject direct `.ps1` execution. Use a child Windows PowerShell process with process-only `-ExecutionPolicy Bypass`; do not use `-File` for the trusted-script transition.

```powershell
$ps51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$basePolicy = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$previous = 'C:\Arvectum\Releases\0.2.3-russian-production'
$policyOut = 'C:\Arvectum\Evidence\APL-WIN-014\final-0.2.4-policy'
$helper = Join-Path $candidate 'apl_win_014_prepare_0_2_4_supplemental_policy.ps1'
$contract = Get-Content -LiteralPath (Join-Path $candidate 'physical_test_contract.json') -Raw | ConvertFrom-Json
$runtime = Join-Path $candidate ([string]$contract.inno_runtime_filename)

& $ps51 -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    $helper `
    -CandidateDirectory $candidate `
    -BasePolicyId $basePolicy `
    -PreviousReleaseDirectory $previous `
    -RuntimePath $runtime `
    -OutputDirectory $policyOut
```

The authoring helper fails closed unless the sealed candidate, canonical predecessor Setup, **candidate-derived Inno runtime**, physical runner, maintenance helpers, deterministic uninstaller, and base PolicyID all agree with the contract. It creates a `Level Hash` multiple-policy supplemental, keeps script enforcement enabled, and writes `trust-pack.json`, `POLICY_TO_DEPLOY.txt`, the supplemental XML/`.cip`, and `SHA256SUMS.txt`.

The helper **does not deploy policy**, remove policy, install/uninstall the product, or weaken Windows protection.

## Phase B — explicit lab-owner deployment

Read the generated trust record and deploy the exact `.cip`:

```powershell
$trust = Get-Content -LiteralPath "$policyOut\trust-pack.json" -Raw | ConvertFrom-Json
$cip = Join-Path $policyOut ([string]$trust.supplemental_policy_cip)
& "$env:SystemRoot\System32\CiTool.exe" --update-policy $cip
& "$env:SystemRoot\System32\CiTool.exe" -lp -json
```

Do not continue unless:

- base PolicyID `dc1c604c-46ea-40b7-9f47-cf582b225d5e` is on disk, authorized, and enforced;
- the generated `supplemental_policy_id` is on disk, authorized, and enforced;
- the base policy is not in Audit mode;
- the base policy still allows supplemental policies.

## Phase C — run the remaining physical gates

Use a fresh evidence directory. Reconfirm the Phase 0 predecessor precondition before invoking the runner. Launch the exact-hash trusted runner **without `-File`** so Windows PowerShell does not attempt cross-language-mode local-scope/dot-sourced execution.

```powershell
$evidence = 'C:\Arvectum\Evidence\APL-WIN-014\final-0.2.4'
$runner = Join-Path $candidate 'apl_win_014_final_0_2_4_physical.ps1'

& $ps51 -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    $runner `
    -CandidateDirectory $candidate `
    -BasePolicyId ([string]$trust.base_policy_id) `
    -CandidateSupplementalPolicyId ([string]$trust.supplemental_policy_id) `
    -PreviousReleaseDirectory $previous `
    -EvidenceDirectory $evidence `
    -IsolatedAcceptanceEnvironment
```

The physical runner must observe the already-installed exact 0.2.3 predecessor and then prove:

1. exact sealed 0.2.3 predecessor identity;
2. real `0.2.3 -> 0.2.4` upgrade under enforced App Control;
3. exact installed 0.2.4 identity and registration;
4. real application start, PAC server on `127.0.0.1:8082`, and exact WinINET `AutoConfigURL`;
5. rollback and removal of governed PAC/WinINET state;
6. repair from the exact cached 0.2.4 Setup;
7. uninstall;
8. zero Arvectum-related Code Integrity event `3077` blocks from the run window;
9. base and candidate supplemental App Control policies still on disk, authorized, and enforced after the lifecycle.

The runner never deploys or removes App Control policy. If the install root is absent, **do not accept a final run that falls back to installing 0.2.3**; stop and restore the exact predecessor precondition first.

## PASS evidence

Canonical result:

```text
C:\Arvectum\Evidence\APL-WIN-014\final-0.2.4\apl-win-014-final-0.2.4-physical-result.json
```

APL-WIN-014 physical acceptance is complete only when that JSON records `result = PASS`, every lifecycle/App Control sub-gate is `PASS`, and `code_integrity_3077_count = 0`.

Preserve the complete candidate directory, policy authoring directory, physical evidence directory, workflow run ID, workflow artifact SHA-256, predecessor identity evidence, candidate-derived runtime evidence, and final `main` commit as the immutable acceptance record.

## Fail-closed rule

Any identity mismatch, missing file, wrong predecessor, wrong or non-candidate-derived runtime, unauthorized/missing policy, Audit mode, occupied governed port, failed PAC/WinINET transition, changed installed byte, Code Integrity 3077 event, residual lifecycle state, or incomplete gate is **BLOCK**. Do not weaken Windows protection and do not replace a failed byte with an unsealed build. Preserve failed evidence and use a new evidence/output directory for a deliberate rerun.
