<# Static fail-closed contract for the accepted Inno runtime hash in V10.6.4/V10.7 policy authoring. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$expectedRuntimeSha = 'b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8'
$expectedRuntimeSize = '4473344'
$expectedInnoCommit = 'cfdf48923178df4b4f040e038b423aa555a61ffc'
$expectedEvidenceRun = '33669452947'

$helper = Get-Content -LiteralPath (Join-Path $scriptDir 'runtime_hash_validation.ps1') -Raw
foreach ($needle in @($expectedRuntimeSha, $expectedRuntimeSize, $expectedInnoCommit, $expectedEvidenceRun, 'static_equals_behavioral', 'derived_runtime_crc_matches_offset_table', 'compressed_block_all_chunk_crcs_pass')) {
    if ($helper -notlike "*$needle*") { throw "Runtime validation helper is missing required anchor: $needle" }
}

$bootstrap = Get-Content -LiteralPath (Join-Path $scriptDir 'prepare_v10_6_4_bootstrap_on_demo.ps1') -Raw
foreach ($needle in @('RuntimePath', 'runtime_hash_validation.ps1', 'Get-AplWin014RuntimeHashMaterial', '$runtime.filename', 'hash_policy_integrated=$true', 'bootstrap-authoring.v4')) {
    if ($bootstrap -notlike "*$needle*") { throw "V10.6.4 bootstrap authoring is missing runtime integration contract: $needle" }
}
if ($bootstrap -notmatch 'ExpectedHashRuleFileNames\s+@\([^\r\n]*\$runtime\.filename') { throw 'V10.6.4 bootstrap validator is not explicitly bound to the runtime filename.' }

$deploy = Get-Content -LiteralPath (Join-Path $scriptDir 'install_v10_6_4_bootstrap_on_demo.ps1') -Raw
foreach ($needle in @('bootstrap-authoring.v4', 'hash_policy_integrated', 'derived_runtime_sha256', 'official_inno_resolved_commit', 'evidence_workflow_run_id')) {
    if ($deploy -notlike "*$needle*") { throw "V10.6.4 deploy validation is missing runtime provenance contract: $needle" }
}

$final = Get-Content -LiteralPath (Join-Path $scriptDir 'prepare_v10_7_final_on_demo.ps1') -Raw
foreach ($needle in @('RuntimePath', 'runtime_hash_validation.ps1', 'Get-AplWin014RuntimeHashMaterial', 'expectedPeEntries', '$runtime.filename', 'hash_policy_integrated=$true', 'v10.7-final-authoring.v3')) {
    if ($final -notlike "*$needle*") { throw "V10.7 final authoring is missing runtime integration contract: $needle" }
}
if ($final -notmatch 'expectedPolicyNames\s*=\s*@\(\$expectedPeNames\s*\+\s*\$runtime\.filename\)') { throw 'V10.7 final policy expected-name set does not include the runtime.' }
if ($final -notmatch 'ExpectedHashRuleFileNames\s+\$expectedPolicyNames') { throw 'V10.7 final validator is not bound to the runtime-inclusive policy name set.' }

$runtimeEvidence = Get-Content -LiteralPath (Join-Path $scriptDir 'derived-runtime\runtime-static-evidence.json') -Raw | ConvertFrom-Json
if ($runtimeEvidence.derived_runtime_sha256 -ine $expectedRuntimeSha) { throw 'Committed runtime evidence SHA256 drifted.' }
if ($runtimeEvidence.behavioral_runtime_sha256 -ine $expectedRuntimeSha) { throw 'Behavioral runtime anchor drifted.' }
if ($runtimeEvidence.derived_runtime_size -ne 4473344 -or $runtimeEvidence.behavioral_runtime_size -ne 4473344) { throw 'Committed runtime evidence size drifted.' }
if ($runtimeEvidence.static_equals_behavioral -ne $true) { throw 'Committed runtime evidence no longer proves static == behavioral.' }

Write-Host 'RESULT: PASS'
