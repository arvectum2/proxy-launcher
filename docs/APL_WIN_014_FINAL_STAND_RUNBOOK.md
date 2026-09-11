# APL-WIN-014 final 0.2.4 physical acceptance

Status: **READY FOR ONE FINAL ARVECTUM-DEMO PHYSICAL EXECUTION**

This runbook is the canonical final physical procedure for APL-WIN-014. It replaces the historical 0.2.2/0.2.3 final-stand sequence. The product candidate is **0.2.4** and is produced once by `.github/workflows/apl-win-014-final-0-2-4.yml`; the same sealed bytes are used by CI and by the physical stand.

The dedicated/isolated Windows 11 host is `ARVECTUM-DEMO`. Its canonical base App Control policy is `dc1c604c-46ea-40b7-9f47-cf582b225d5e`. The base policy must remain **Enforced**, on disk, authorized, and configured with **Enabled:Allow Supplemental Policies**. Never switch it to Audit mode and never disable Smart App Control, App Control for Business, Defender, or another Windows protection to make a gate pass.

CryptoPro/Rutoken is not required for this final endpoint acceptance. Russian release signing is an upstream release-control concern; the remaining gate is exact-byte Windows lifecycle behavior under enforced App Control.

## Inputs

Use exactly these inputs:

- the single ZIP artifact from workflow **APL-WIN-014 final 0.2.4**;
- canonical sealed predecessor directory `C:\Arvectum\Releases\0.2.3-russian-production`, containing `Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe` with SHA-256 `5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414`;
- accepted Inno Setup 6.7.1 runtime material at `C:\Arvectum\Evidence\APL-WIN-014\reference-bootstrap-final\runtime\inno-setup-6.7.1-runtime-stub.exe`, SHA-256 `b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8`;
- Windows ConfigCI cmdlets and `CiTool.exe`.

Extract the workflow ZIP into a new immutable candidate directory, for example:

```powershell
$candidate = 'C:\Arvectum\Releases\APL-WIN-014\final-0.2.4'
```

Do not edit, rebuild, rename, or substitute files inside the extracted candidate. `candidate_evidence.json`, `physical_test_contract.json`, and `SHA256SUMS.txt` are the sealed identity contract.

## Phase A — author the exact 0.2.4 supplemental policy

Run elevated Windows PowerShell 5.1. The helper is included in the sealed candidate itself:

```powershell
$basePolicy = [Guid]'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$previous = 'C:\Arvectum\Releases\0.2.3-russian-production'
$runtime = 'C:\Arvectum\Evidence\APL-WIN-014\reference-bootstrap-final\runtime\inno-setup-6.7.1-runtime-stub.exe'
$policyOut = 'C:\Arvectum\Evidence\APL-WIN-014\final-0.2.4-policy'

& "$candidate\apl_win_014_prepare_0_2_4_supplemental_policy.ps1" `
    -CandidateDirectory $candidate `
    -BasePolicyId $basePolicy `
    -PreviousReleaseDirectory $previous `
    -RuntimePath $runtime `
    -OutputDirectory $policyOut
```

The authoring helper fails closed unless all of the following agree exactly with the sealed contract:

- 0.2.4 Setup and frozen application EXE;
- upgrade and uninstall maintenance helpers;
- deterministic 0.2.4 `unins000.exe` captured by the same candidate build;
- physical acceptance runner;
- canonical 0.2.3 predecessor Setup;
- accepted Inno Setup 6.7.1 runtime;
- canonical base PolicyID.

It then creates a `Level Hash` multiple-policy supplemental, explicitly keeps script enforcement enabled, binds it to the canonical base policy, converts it to `.cip`, and writes:

- `trust-pack.json`;
- `POLICY_TO_DEPLOY.txt`;
- the supplemental XML and `.cip`;
- `SHA256SUMS.txt`.

The helper **does not deploy policy**, remove policy, install/uninstall the product, or weaken Windows protection.

A successful Phase A ends with:

```text
APL-WIN-014 final 0.2.4 App Control trust authoring: PASS
Policy deployed: NO
Security controls modified: NO
```

## Phase B — explicit lab-owner deployment

Read the generated trust record:

```powershell
$trust = Get-Content -LiteralPath "$policyOut\trust-pack.json" -Raw | ConvertFrom-Json
$cip = Join-Path $policyOut ([string]$trust.supplemental_policy_cip)
```

Confirm the `.cip` hash equals `supplemental_policy_cip_sha256` in `trust-pack.json`, then deploy that exact file through the approved lab App Control management path. For the standalone isolated ARVECTUM-DEMO procedure the Windows primitive is:

```powershell
& "$env:SystemRoot\System32\CiTool.exe" --update-policy $cip
```

Then inspect live policy state:

```powershell
& "$env:SystemRoot\System32\CiTool.exe" -lp -json
```

Do not continue unless:

- base PolicyID `dc1c604c-46ea-40b7-9f47-cf582b225d5e` is on disk, authorized, and enforced;
- the generated `supplemental_policy_id` is on disk, authorized, and enforced;
- the base policy is not in Audit mode;
- the base policy still allows supplemental policies.

The execution runner repeats these checks fail-closed before touching the product.

## Phase C — run the only remaining physical gates

Use a fresh evidence directory. From elevated Windows PowerShell 5.1:

```powershell
$evidence = 'C:\Arvectum\Evidence\APL-WIN-014\final-0.2.4'

& "$candidate\apl_win_014_final_0_2_4_physical.ps1" `
    -CandidateDirectory $candidate `
    -BasePolicyId ([Guid]$trust.base_policy_id) `
    -CandidateSupplementalPolicyId ([Guid]$trust.supplemental_policy_id) `
    -PreviousReleaseDirectory $previous `
    -EvidenceDirectory $evidence `
    -IsolatedAcceptanceEnvironment
```

The physical runner verifies the candidate evidence again and executes only the gates that cannot be proved by hosted CI:

1. exact sealed `0.2.3` predecessor installation;
2. real `0.2.3 -> 0.2.4` upgrade;
3. exact installed 0.2.4 identity and registration;
4. real application start, PAC server on `127.0.0.1:8082`, and exact WinINET `AutoConfigURL`;
5. rollback and removal of governed PAC/WinINET state;
6. repair from the exact cached 0.2.4 Setup;
7. uninstall;
8. zero Arvectum-related Code Integrity event `3077` blocks from the run window;
9. base and candidate supplemental App Control policies still on disk, authorized, and enforced after the lifecycle.

The runner never deploys or removes App Control policy.

## PASS evidence

Canonical result:

```text
C:\Arvectum\Evidence\APL-WIN-014\final-0.2.4\apl-win-014-final-0.2.4-physical-result.json
```

APL-WIN-014 physical acceptance is complete only when that JSON records `result = PASS` and every lifecycle/App Control sub-gate is `PASS` with `code_integrity_3077_count = 0`.

Preserve the complete candidate directory, policy authoring directory, physical evidence directory, workflow run ID, workflow artifact SHA-256, and final `main` commit as the immutable acceptance record.

## Fail-closed rule

Any identity mismatch, missing file, wrong predecessor, wrong runtime, unauthorized/missing policy, Audit mode, occupied governed port, failed PAC/WinINET transition, changed installed byte, Code Integrity 3077 event, residual lifecycle state, or incomplete gate is **BLOCK**. Do not weaken Windows protection and do not replace the failed byte with an unsealed build. Preserve the failed evidence and use a new evidence/output directory for a deliberate rerun.
