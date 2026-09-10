<#
.SYNOPSIS
    Validate the exact Inno Setup 6.7.1 child runtime material used by APL-WIN-014.
.DESCRIPTION
    The supplied extraction evidence must be produced from the exact canonical
    production Setup and the runtime bytes must equal the independently proven
    static/behavioral Inno 6.7.1 anchor.

    The validation function remains available for trusted callers that intentionally
    dot-source this file outside an App Control language-mode boundary. The canonical
    APL-WIN-014 physical-stand path invokes this file as a separate PowerShell process
    with -AsJson so App Control can evaluate this script independently and no command
    definitions cross FullLanguage/ConstrainedLanguage scopes.
#>
[CmdletBinding()]
param(
    [string]$RuntimePath = '',
    [string]$RuntimeEvidencePath = '',
    [string]$ExpectedSetupSha256 = '',
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ArvectumInnoRuntimeMaterial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$RuntimePath,
        [Parameter(Mandatory = $true)] [string]$RuntimeEvidencePath,
        [Parameter(Mandatory = $true)] [string]$ExpectedSetupSha256
    )

    $expectedRuntimeSize = 4473344
    $expectedRuntimeSha256 = 'b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8'
    $expectedRuntimeCrc32 = '021edadf'
    $expectedInnoTag = 'is-6_7_1'
    $expectedInnoCommit = 'cfdf48923178df4b4f040e038b423aa555a61ffc'
    $evidenceWorkflowRun = 33669452947
    $behavioralWorkflowRun = 33666343748
    $historicalAnchorSetupSha256 = '7e7640fe434067415840a154cfbeba0df443caf155fed38cff7ede1bc7d7d600'

    $RuntimePath = (Resolve-Path -LiteralPath $RuntimePath).Path
    $RuntimeEvidencePath = (Resolve-Path -LiteralPath $RuntimeEvidencePath).Path
    $evidence = Get-Content -LiteralPath $RuntimeEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json

    $setupHash = ([string]$evidence.sealed_setup_sha256).ToLowerInvariant()
    $runtimeHash = ([string]$evidence.derived_runtime_sha256).ToLowerInvariant()
    $runtimeCrc = ([string]$evidence.derived_runtime_crc32).ToLowerInvariant()
    $actualRuntimeHash = (Get-FileHash -LiteralPath $RuntimePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $actualRuntimeSize = [long](Get-Item -LiteralPath $RuntimePath).Length

    if ($setupHash -ne $ExpectedSetupSha256.ToLowerInvariant()) {
        throw 'Inno runtime extraction evidence is not bound to the exact canonical production Setup.'
    }
    if ([long]$evidence.derived_runtime_size -ne $expectedRuntimeSize -or [long]$evidence.uncompressed_size_exe -ne $expectedRuntimeSize) {
        throw 'Inno runtime extraction evidence size does not match the accepted 6.7.1 runtime.'
    }
    if ($runtimeHash -ne $expectedRuntimeSha256 -or $runtimeCrc -ne $expectedRuntimeCrc32) {
        throw 'Inno runtime extraction evidence does not match the accepted static/behavioral anchor.'
    }
    if ($actualRuntimeSize -ne $expectedRuntimeSize -or $actualRuntimeHash -ne $expectedRuntimeSha256) {
        throw 'Supplied Inno runtime binary does not match the accepted static/behavioral anchor.'
    }
    if ([int]$evidence.compressed_block_chunk_count -le 0) {
        throw 'Inno runtime extraction evidence does not contain a valid compressed-block traversal.'
    }

    return [pscustomobject]@{
        filename = 'inno-setup-6.7.1-runtime-stub.exe'
        path = $RuntimePath
        size = $expectedRuntimeSize
        sha256 = $expectedRuntimeSha256
        crc32 = $expectedRuntimeCrc32
        source_setup_sha256 = $setupHash
        extraction_evidence_path = $RuntimeEvidencePath
        extraction_evidence_sha256 = (Get-FileHash -LiteralPath $RuntimeEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
        observed_compressed_chunk_count = [int]$evidence.compressed_block_chunk_count
        official_inno_tag = $expectedInnoTag
        official_inno_commit = $expectedInnoCommit
        evidence_workflow_run = $evidenceWorkflowRun
        behavioral_workflow_run = $behavioralWorkflowRun
        historical_anchor_setup_sha256 = $historicalAnchorSetupSha256
        behavioral_anchor_workflow_run = $behavioralWorkflowRun
        behavioral_anchor_setup_sha256 = $historicalAnchorSetupSha256
        static_to_behavioral_anchor = 'PASS'
    }
}

if ($AsJson) {
    foreach ($required in @(
        @{ Name = 'RuntimePath'; Value = $RuntimePath },
        @{ Name = 'RuntimeEvidencePath'; Value = $RuntimeEvidencePath },
        @{ Name = 'ExpectedSetupSha256'; Value = $ExpectedSetupSha256 }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
            throw "Standalone runtime validation requires -$($required.Name)."
        }
    }

    $material = Get-ArvectumInnoRuntimeMaterial `
        -RuntimePath $RuntimePath `
        -RuntimeEvidencePath $RuntimeEvidencePath `
        -ExpectedSetupSha256 $ExpectedSetupSha256

    $material | ConvertTo-Json -Depth 8 -Compress
}
