<#
.SYNOPSIS
    Prepare all immutable APL-WIN-014 physical-stand inputs without deploying policy.
.DESCRIPTION
    One authoring entry point for the isolated ARVECTUM-DEMO Windows 11 stand.
    It recovers the exact historical 0.2.2 P0.4 baseline, authors its exact-hash
    supplemental policy, derives the exact Inno Setup 6.7.1 production child runtime,
    authors the current ReferenceFullHash policy, and seals a stand-state manifest.

    This script never installs/uninstalls the product, never calls CiTool policy update
    or removal, and never weakens Smart App Control, App Control for Business, Defender,
    or any policy option. Deployment of the two emitted .cip files is a separate explicit
    lab-owner action.
#>
[CmdletBinding()]
param(
    [Guid]$BasePolicyId = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e',
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$ReleaseDirectory = 'C:\Arvectum\Releases\0.2.3-russian-production',
    [string]$InstalledRoot = '',
    [string]$RunRoot = 'C:\Arvectum\Evidence\APL-WIN-014\final-stand',
    [string]$HistoricalPackageZipPath = '',
    [string]$HistoricalQaEvidencePath = '',
    [string]$PythonCommand = 'python.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedBasePolicyId = [Guid]'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$ExpectedSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
$ExpectedAppSha256 = 'f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a'
$ExpectedRuntimeSha256 = 'b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8'
$ExpectedLegacyCommit = '0ea08d9c815da36d0175f62db153de78f89731fc'
$ExpectedLegacyBlobSha1 = '574d3dc5f90a116555e3a72ff3288c31c19d3dc7'

if ($env:OS -ne 'Windows_NT') { throw 'Final stand preparation must run on Windows.' }
if ($BasePolicyId -ne $ExpectedBasePolicyId) {
    throw "This governed ARVECTUM-DEMO preparation is bound to base policy $ExpectedBasePolicyId."
}
if (Test-Path -LiteralPath $RunRoot) {
    throw "RunRoot already exists; refusing to overwrite prior stand evidence: $RunRoot"
}

$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$ReleaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
if (-not $InstalledRoot) { $InstalledRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ArvectumProxyLauncher' }
$InstalledRoot = (Resolve-Path -LiteralPath $InstalledRoot).Path

$recover = Join-Path $PSScriptRoot 'windows_app_control_recover_0_2_2_baseline.ps1'
$baselinePack = Join-Path $PSScriptRoot 'windows_app_control_legacy_baseline_trust_pack.ps1'
$currentPack = Join-Path $PSScriptRoot 'windows_app_control_prepare_production_runtime_trust.ps1'
$runtimeVerifier = Join-Path $PSScriptRoot 'windows_app_control_verify_runtime_trust_pack.ps1'
foreach ($required in @($recover,$baselinePack,$currentPack,$runtimeVerifier)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required stand tool is missing: $required" }
}

$baselineReleaseDir = Join-Path $RunRoot 'baseline-release'
$baselineRecoveryDir = Join-Path $RunRoot 'baseline-recovery'
$baselineTrustDir = Join-Path $RunRoot 'baseline-trust-pack'
$runtimeDir = Join-Path $RunRoot 'runtime'
$currentTrustDir = Join-Path $RunRoot 'current-trust-pack'
$finalEvidenceDir = Join-Path $RunRoot 'final-evidence'

$sourceCommit = ''
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git -and (Test-Path -LiteralPath (Join-Path $RepositoryRoot '.git'))) {
    $sourceCommit = ((& git -C $RepositoryRoot rev-parse HEAD 2>&1) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'Unable to resolve repository HEAD for stand evidence.' }
}

$hasHistoricalPackage = -not [string]::IsNullOrWhiteSpace($HistoricalPackageZipPath)
$hasHistoricalQa = -not [string]::IsNullOrWhiteSpace($HistoricalQaEvidencePath)
if ($hasHistoricalPackage -xor $hasHistoricalQa) {
    throw 'Historical stand-mode recovery requires BOTH package ZIP and QA evidence paths.'
}
if (-not $sourceCommit -and -not $hasHistoricalPackage) {
    throw 'No usable Git working copy is available; supply both exact historical files for stand-mode baseline recovery.'
}

New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null

Write-Host '=== 1/3 Recover exact historical 0.2.2 P0.4 baseline ==='
$recoverArgs = @{
    RepositoryRoot = $RepositoryRoot
    OutputDirectory = $baselineReleaseDir
    EvidenceDirectory = $baselineRecoveryDir
}
if ($hasHistoricalPackage) {
    $recoverArgs.HistoricalPackageZipPath = $HistoricalPackageZipPath
    $recoverArgs.HistoricalQaEvidencePath = $HistoricalQaEvidencePath
}
& $recover @recoverArgs
$baselineManifestPath = Join-Path $baselineRecoveryDir 'apl-win-014-0.2.2-baseline-recovery.json'
if (-not (Test-Path -LiteralPath $baselineManifestPath -PathType Leaf)) { throw 'Baseline recovery manifest is missing.' }
$baselineManifest = Get-Content -LiteralPath $baselineManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$baselineManifest.result -ne 'PASS' -or [string]$baselineManifest.source.commit -ne $ExpectedLegacyCommit -or [string]$baselineManifest.source.git_blob_sha1 -ne $ExpectedLegacyBlobSha1) {
    throw 'Recovered baseline does not match the governed historical identity.'
}

Write-Host '=== 2/3 Author exact historical baseline supplemental policy ==='
& $baselinePack -BaselineManifestPath $baselineManifestPath -BasePolicyId $BasePolicyId -OutputDirectory $baselineTrustDir
$baselineTrustManifestPath = Join-Path $baselineTrustDir 'trust-pack.json'
if (-not (Test-Path -LiteralPath $baselineTrustManifestPath -PathType Leaf)) { throw 'Baseline trust-pack manifest is missing.' }
$baselineTrust = Get-Content -LiteralPath $baselineTrustManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$baselineTrust.result -ne 'PASS' -or ([Guid]([string]$baselineTrust.base_policy_id)) -ne $BasePolicyId) {
    throw 'Baseline trust pack is not a PASS record for the canonical base policy.'
}
$baselinePolicyId = [Guid]([string]$baselineTrust.supplemental_policy_id)
$baselineCip = Join-Path $baselineTrustDir ([string]$baselineTrust.supplemental_policy_cip)
if (-not (Test-Path -LiteralPath $baselineCip -PathType Leaf)) { throw 'Baseline supplemental .cip is missing.' }

Write-Host '=== 3/3 Derive production Inno runtime and author current ReferenceFullHash policy ==='
& $currentPack -BasePolicyId $BasePolicyId -ReleaseDirectory $ReleaseDirectory -InstalledRoot $InstalledRoot -RuntimeDirectory $runtimeDir -TrustPackDirectory $currentTrustDir -PythonCommand $PythonCommand
& $runtimeVerifier -TrustPackDirectory $currentTrustDir

$currentTrustManifestPath = Join-Path $currentTrustDir 'trust-pack.json'
if (-not (Test-Path -LiteralPath $currentTrustManifestPath -PathType Leaf)) { throw 'Current trust-pack manifest is missing.' }
$currentTrust = Get-Content -LiteralPath $currentTrustManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$currentTrust.result -ne 'PASS' -or [string]$currentTrust.mode -ne 'ReferenceFullHash' -or ([Guid]([string]$currentTrust.base_policy_id)) -ne $BasePolicyId) {
    throw 'Current trust pack is not a ReferenceFullHash PASS record for the canonical base policy.'
}
if (([string]$currentTrust.release.installer_sha256).ToLowerInvariant() -ne $ExpectedSetupSha256 -or ([string]$currentTrust.release.application_exe_sha256).ToLowerInvariant() -ne $ExpectedAppSha256) {
    throw 'Current trust pack does not bind the exact production release.'
}
if (([string]$currentTrust.inno_runtime.sha256).ToLowerInvariant() -ne $ExpectedRuntimeSha256) {
    throw 'Current trust pack does not bind the accepted Inno runtime.'
}
$currentPolicyId = [Guid]([string]$currentTrust.supplemental_policy_id)
$currentCip = Join-Path $currentTrustDir ([string]$currentTrust.supplemental_policy_cip)
if (-not (Test-Path -LiteralPath $currentCip -PathType Leaf)) { throw 'Current supplemental .cip is missing.' }

$state = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-final-stand-state.v1'
    task = 'APL-WIN-014'
    prepared_utc = [DateTime]::UtcNow.ToString('o')
    host = $env:COMPUTERNAME
    source_repository = 'arvectum2/proxy-launcher'
    source_commit = $sourceCommit
    base_policy_id = $BasePolicyId.ToString('D')
    release_directory = $ReleaseDirectory
    installed_reference_root = $InstalledRoot
    baseline = [ordered]@{
        manifest_path = $baselineManifestPath
        trust_pack_directory = $baselineTrustDir
        supplemental_policy_id = $baselinePolicyId.ToString('D')
        supplemental_policy_cip = $baselineCip
        supplemental_policy_cip_sha256 = (Get-FileHash -LiteralPath $baselineCip -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    current = [ordered]@{
        trust_pack_directory = $currentTrustDir
        runtime_directory = $runtimeDir
        supplemental_policy_id = $currentPolicyId.ToString('D')
        supplemental_policy_cip = $currentCip
        supplemental_policy_cip_sha256 = (Get-FileHash -LiteralPath $currentCip -Algorithm SHA256).Hash.ToLowerInvariant()
        production_setup_sha256 = $ExpectedSetupSha256
        application_sha256 = $ExpectedAppSha256
        inno_runtime_sha256 = $ExpectedRuntimeSha256
    }
    final_evidence_directory = $finalEvidenceDir
    policy_deployment = 'NOT PERFORMED'
    security_controls_modified = $false
    product_lifecycle_modified = $false
    result = 'PREPARED'
}
$statePath = Join-Path $RunRoot 'stand-state.json'
$state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding UTF8

$deployment = @"
APL-WIN-014 FINAL PHYSICAL STAND - POLICIES TO DEPLOY
======================================================

Base policy (must already be active, enforced, and permit supplemental policies):
  $($BasePolicyId.ToString('D'))

Deploy BOTH supplemental policies through the approved lab App Control management path:

1. Historical 0.2.2 P0.4 exact-hash supplemental
   Policy ID: $($baselinePolicyId.ToString('D'))
   CIP: $baselineCip
   SHA256: $($state.baseline.supplemental_policy_cip_sha256)

2. Current 0.2.3 ReferenceFullHash supplemental
   Policy ID: $($currentPolicyId.ToString('D'))
   CIP: $currentCip
   SHA256: $($state.current.supplemental_policy_cip_sha256)

DO NOT disable Smart App Control, Defender, App Control, or switch the base policy to Audit mode.
This preparation script did NOT deploy policy and did NOT modify security controls.

After both supplemental policies are active/on-disk and authorized, run:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\windows_app_control_run_final_stand.ps1 -StatePath "$statePath" -IsolatedAcceptanceEnvironment
"@
$deploymentPath = Join-Path $RunRoot 'POLICIES_TO_DEPLOY.txt'
Set-Content -LiteralPath $deploymentPath -Value $deployment -Encoding UTF8

$stateHash = (Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash.ToLowerInvariant()
$deploymentHash = (Get-FileHash -LiteralPath $deploymentPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath (Join-Path $RunRoot 'SHA256SUMS.txt') -Encoding ASCII -Value @(
    "$stateHash  stand-state.json",
    "$deploymentHash  POLICIES_TO_DEPLOY.txt"
)

Write-Host ''
Write-Host 'APL-WIN-014 final stand preparation: PREPARED'
Write-Host "Stand state: $statePath"
Write-Host "Deployment instructions: $deploymentPath"
Write-Host "Baseline supplemental PolicyID: $($baselinePolicyId.ToString('D'))"
Write-Host "Current supplemental PolicyID: $($currentPolicyId.ToString('D'))"
Write-Host 'Policy deployment: NOT PERFORMED'
Write-Host 'Security controls modified: NO'
Write-Host 'Product lifecycle modified: NO'
