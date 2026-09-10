<# Fail-closed validation for the exact Inno Setup 6.7.1 child runtime used by APL-WIN-014 hash policies. #>
#Requires -Version 5.1

function Get-AplWin014RuntimeHashMaterial {
    [CmdletBinding()]
    param(
        [string]$RuntimePath = '',
        [string]$ScriptDirectory = ''
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($RuntimePath -eq '' -or -not (Test-Path -LiteralPath $RuntimePath -PathType Leaf)) {
        throw 'RuntimePath is required and must point to the exact derived Inno runtime binary.'
    }
    if ($ScriptDirectory -eq '' -or -not (Test-Path -LiteralPath $ScriptDirectory -PathType Container)) {
        throw 'ScriptDirectory is required and must exist.'
    }

    $sealPath = Join-Path $ScriptDirectory 'expected_hashes.json'
    $evidencePath = Join-Path $ScriptDirectory 'derived-runtime\runtime-static-evidence.json'
    foreach ($requiredPath in @($sealPath, $evidencePath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required runtime provenance file is missing: $requiredPath"
        }
    }

    $seal = Get-Content -LiteralPath $sealPath -Raw | ConvertFrom-Json
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json

    $expectedRuntimeSize = 4473344
    $expectedRuntimeSha256 = 'b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8'
    $expectedInnoTag = 'is-6_7_1'
    $expectedInnoCommit = 'cfdf48923178df4b4f040e038b423aa555a61ffc'
    $expectedEvidenceRun = 33669452947

    if ($evidence.schema -ne 'arvectum.proxy.apl-win-014-v10.6.4-runtime-static-evidence.v1') { throw 'Unexpected Inno runtime evidence schema.' }
    if ($evidence.task -ne 'APL-WIN-014') { throw 'Runtime evidence task mismatch.' }
    if ($evidence.official_inno_tag -ne $expectedInnoTag -or $evidence.official_inno_resolved_commit -ne $expectedInnoCommit) { throw 'Runtime evidence Inno source identity mismatch.' }
    if ($evidence.evidence_workflow_run_id -ne $expectedEvidenceRun -or $evidence.evidence_workflow_run_attempt -ne 1) { throw 'Runtime evidence workflow identity mismatch.' }
    if ($evidence.static_equals_behavioral -ne $true) { throw 'Runtime evidence does not prove static == behavioral.' }
    if ($evidence.derived_runtime_crc_matches_offset_table -ne $true) { throw 'Runtime evidence CRC proof is not PASS.' }
    if ($evidence.compressed_block_header_crc_result -ne $true -or $evidence.compressed_block_all_chunk_crcs_pass -ne $true) { throw 'Runtime evidence compressed-stream CRC proof is not PASS.' }
    if ($evidence.inverse_call_transform_applied -ne $true) { throw 'Runtime evidence inverse call transform proof is missing.' }
    if ($evidence.derived_runtime_size -ne $expectedRuntimeSize -or $evidence.behavioral_runtime_size -ne $expectedRuntimeSize) { throw 'Runtime evidence size mismatch.' }
    if ($evidence.derived_runtime_sha256 -ine $expectedRuntimeSha256 -or $evidence.behavioral_runtime_sha256 -ine $expectedRuntimeSha256) { throw 'Runtime evidence hash mismatch.' }
    if ($evidence.sealed_setup_filename -ne $seal.files.setup.filename -or $evidence.sealed_setup_size -ne $seal.files.setup.size -or $evidence.sealed_setup_sha256 -ine $seal.files.setup.sha256) { throw 'Runtime evidence is not bound to the sealed V10.6.4 setup.' }
    if ($evidence.product_rebuilt -ne $false -or $evidence.candidate_rerun -ne $false -or $evidence.stand_modified -ne $false) { throw 'Runtime evidence unexpectedly reports product/candidate/stand mutation.' }

    $runtime = Get-Item -LiteralPath $RuntimePath
    if ($runtime.Length -ne $expectedRuntimeSize) { throw "Runtime binary size mismatch: $($runtime.Length)" }

    $certUtil = Join-Path $env:SystemRoot 'System32\certutil.exe'
    if (-not (Test-Path -LiteralPath $certUtil -PathType Leaf)) { throw 'certutil.exe not found in System32.' }
    $output = & $certUtil -hashfile $RuntimePath SHA256
    if ($LASTEXITCODE -ne 0) { throw 'certutil SHA256 failed for runtime binary.' }
    $hashes = @($output | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' })
    if ($hashes.Count -ne 1) { throw "certutil SHA256 produced $($hashes.Count) runtime hash candidates." }
    if ($hashes[0] -ine $expectedRuntimeSha256) { throw 'Runtime binary SHA256 does not match the accepted static/behavioral anchor.' }

    return [ordered]@{
        filename='inno-setup-6.7.1-runtime-stub.exe'
        source_path=$RuntimePath
        size=$expectedRuntimeSize
        sha256=$expectedRuntimeSha256
        official_inno_tag=$expectedInnoTag
        official_inno_commit=$expectedInnoCommit
        evidence_workflow_run=$expectedEvidenceRun
        evidence_workflow_attempt=1
        static_equals_behavioral=$true
    }
}
