# APL-WIN-014 final physical stand

Status: **READY FOR ARVECTUM-DEMO PHYSICAL EXECUTION**

This runbook is only for the dedicated/isolated Windows 11 `ARVECTUM-DEMO` acceptance host. The canonical lab base App Control policy is `dc1c604c-46ea-40b7-9f47-cf582b225d5e` and must remain **Enforced**, on disk, and configured with **Enabled:Allow Supplemental Policies**. Do not switch it to Audit mode and do not disable Smart App Control, App Control for Business, Defender, or another Windows protection.

Windows PowerShell 5.1 on an enforced App Control host may keep the interactive shell in `ConstrainedLanguage` while policy-authorized scripts run in `FullLanguage`. For that reason the canonical stand commands use the PowerShell call operator (`&`) and do not launch trusted `.ps1` entrypoints through `powershell.exe -File`, whose Windows PowerShell 5.1 semantics can trigger a mixed-language dot-source boundary.

Russian detached-signature verification is an **Arvectum release/owner-station control**, not an endpoint prerequisite. `ARVECTUM-DEMO`, customer IT, and ordinary product users do not need CryptoPro CSP or a Rutoken. The acceptance host receives the exact canonical signing-evidence JSON produced by the governed upstream signing process, verifies its fixed SHA-256 and acceptance fields, and independently verifies the exact release bytes against the sealed release identities.

## Phase A — prepare immutable stand state

Prerequisites:

- canonical repository checkout at the intended source commit;
- exact Russian production release directory at `C:\Arvectum\Releases\0.2.3-russian-production`;
- exact canonical owner-station signing-evidence JSON for `v0.2.3-ru.2`, SHA-256 `67d379db11a238960b9324c8054e73790cf18b1eaa85db8c04a9226bb27bc58e`;
- exact current `0.2.3` reference installation at `Documents\ArvectumProxyLauncher` for `ReferenceFullHash` capture;
- Windows ConfigCI cmdlets;
- Python plus `pefile==2024.8.26`;
- either local Git history containing the governed `0.2.2 P0.4` baseline or both exact historical files accepted by the recovery tool.

Run from elevated Windows PowerShell 5.1 in the repository root, supplying the exact signing evidence:

```powershell
& .\tools\windows_app_control_prepare_final_stand.ps1 `
    -SigningEvidencePath 'C:\Arvectum\Evidence\APL-WIN-014\release-signing\windows-russian-signing-evidence.json'
```

The script fails closed if the evidence file is missing or its SHA-256 differs from the canonical `67d379...` identity. It records `russian_release_provenance = PREVERIFIED_EXACT_HASH_BOUND` and `local_cryptopro_verification = NOT_REQUIRED`; it never converts an absent local CryptoPro verification into a false local PASS.

The script creates `C:\Arvectum\Evidence\APL-WIN-014\final-stand\stand-state.json` and `POLICIES_TO_DEPLOY.txt`. It does **not** deploy policy, install/uninstall the product, or change Windows protection state.

## Phase B — explicit lab-owner policy deployment

Open `POLICIES_TO_DEPLOY.txt`. It contains the generated PolicyID, exact `.cip` path, and SHA-256 for both required supplemental policies:

1. historical `0.2.2 P0.4` exact-hash supplemental;
2. current `0.2.3` `ReferenceFullHash` supplemental, including the exact statically-derived Inno Setup 6.7.1 child runtime.

Deploy **both** `.cip` files through the approved lab App Control management path. For the existing standalone ARVECTUM-DEMO lab procedure, the relevant Windows primitive is `CiTool.exe --update-policy <exact-cip-path>`. Deployment is intentionally not embedded in either Arvectum orchestration wrapper.

Do not proceed until `CiTool.exe -lp -json` shows the canonical base policy enforced/on-disk and both generated supplemental PolicyIDs on-disk and authorized. The execution wrapper repeats these checks fail-closed.

## Phase C — clean exact reference and run canonical acceptance

Run from the same repository checkout in elevated Windows PowerShell 5.1:

```powershell
& .\tools\windows_app_control_run_final_stand.ps1 -IsolatedAcceptanceEnvironment
```

Before cleanup, the wrapper re-verifies the complete live reference-installation inventory against the generated `ReferenceFullHash` manifest, including the exact application EXE and cached repair Setup. It then rolls back governed proxy state, invokes the exact verified uninstaller, refuses to delete unknown or changed residual files, removes only the canonical Arvectum reference/state directories, and invokes `windows_app_control_local_gate_complete.ps1`.

Final PASS requires all of the following in canonical evidence:

- Inno runtime trust gate: PASS;
- real historical `0.2.2 P0.4 -> 0.2.3` cross-version upgrade: PASS;
- exact current `0.2.3` install/start/PAC/rollback/repair/uninstall lifecycle: PASS;
- zero Arvectum Code Integrity event `3077` blocks;
- App Control remains enforced.

Canonical final evidence is written under `C:\Arvectum\Evidence\APL-WIN-014\final-stand\final-evidence`, including `apl-win-014-final-result.json` and the underlying enforced-gate evidence.

## Fail-closed rule

Any identity mismatch, unexpected file, missing/unauthorized policy, Audit mode, occupied governed port, changed release byte, signing-evidence drift, or incomplete final sub-gate is **BLOCK**, not a reason to weaken Windows protection or substitute another binary. Preserve the failed run directory as evidence and use a new `-RunRoot` for any deliberate rerun.
