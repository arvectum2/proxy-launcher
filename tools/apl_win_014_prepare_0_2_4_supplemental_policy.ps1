<#
.SYNOPSIS
    Author the exact-hash App Control supplemental policy for the final APL-WIN-014 0.2.4 physical acceptance.
.DESCRIPTION
    Fail-closed authoring helper for the dedicated ARVECTUM-DEMO acceptance flow.
    It binds the supplemental policy to the exact sealed 0.2.4 candidate bytes,
    the canonical 0.2.3 predecessor Setup, the candidate-derived Inno Setup child
    runtime, and every exact native PyInstaller one-file binary that is materialized
    under %TEMP%\_MEI* at application startup. It is intentionally compatible with
    PowerShell ConstrainedLanguage because it must run before its own supplemental
    policy is deployed. It never deploys/removes policy and never weakens Windows
    protection.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$CandidateDirectory,
    [Parameter(Mandatory = $true)] [string]$BasePolicyId,
    [string]$PreviousReleaseDirectory = 'C:\Arvectum\Releases\0.2.3-russian-production',
    [string]$RuntimePath = 'C:\Arvectum\Evidence\APL-WIN-014\reference-bootstrap-final\runtime\inno-setup-6.7.1-runtime-stub.exe',
    [string]$OutputDirectory = 'C:\Arvectum\Evidence\APL-WIN-014\final-0.2.4-policy'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256([string]$Path) {
    $fileHash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    return [string]$fileHash.Hash
}

function Normalize-GuidText([object]$Value) {
    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    $text = $text -replace '[{}]', ''
    $text = $text -replace '^\s+', ''
    $text = $text -replace '\s+$', ''
    return $text
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required Windows ConfigCI command is unavailable: $Name"
    }
}

function Get-PolicyIdFromXml([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($text -notmatch '(?i)<PolicyID>\s*([^<]+)\s*</PolicyID>') {
        throw 'Generated App Control policy has no PolicyID.'
    }
    return Normalize-GuidText $Matches[1]
}

function Assert-ExactFile([string]$Path, [string]$ExpectedSha256, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    $actual = Get-Sha256 $Path
    if ($actual -ne $ExpectedSha256) {
        throw "$Label SHA256 mismatch: expected $ExpectedSha256, got $actual"
    }
}

function Copy-ExactFile([string]$Source, [string]$Destination, [string]$ExpectedSha256, [string]$Label) {
    Assert-ExactFile -Path $Source -ExpectedSha256 $ExpectedSha256 -Label $Label
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Assert-ExactFile -Path $Destination -ExpectedSha256 $ExpectedSha256 -Label "$Label staged copy"
}

function Get-UtcTimestamp {
    $utc = Get-CimInstance Win32_UTCTime
    if ($null -eq $utc) { throw 'Unable to obtain UTC time.' }
    return ('{0:D4}-{1:D2}-{2:D2}T{3:D2}:{4:D2}:{5:D2}Z' -f [int]$utc.Year,[int]$utc.Month,[int]$utc.Day,[int]$utc.Hour,[int]$utc.Minute,[int]$utc.Second)
}

if ($env:OS -ne 'Windows_NT') { throw 'APL-WIN-014 0.2.4 App Control authoring must run on Windows.' }
foreach ($cmd in @('New-CIPolicy','Set-CIPolicyIdInfo','Set-CIPolicyVersion','ConvertFrom-CIPolicy')) {
    Assert-Command $cmd
}

$CandidateDirectory = (Resolve-Path -LiteralPath $CandidateDirectory).Path
$PreviousReleaseDirectory = (Resolve-Path -LiteralPath $PreviousReleaseDirectory).Path
$RuntimePath = (Resolve-Path -LiteralPath $RuntimePath).Path
if ($OutputDirectory -notmatch '^(?:[A-Za-z]:\\|\\\\)') {
    throw "Output directory must be absolute: $OutputDirectory"
}
if (Test-Path -LiteralPath $OutputDirectory) {
    throw "Output directory already exists; refusing to overwrite prior policy evidence: $OutputDirectory"
}

$candidateEvidencePath = Join-Path $CandidateDirectory 'candidate_evidence.json'
$contractPath = Join-Path $CandidateDirectory 'physical_test_contract.json'
foreach ($required in @($candidateEvidencePath,$contractPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required sealed candidate metadata is missing: $required" }
}
$candidate = Get-Content -LiteralPath $candidateEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ([string]$candidate.schema -ne 'arvectum.proxy.apl-win-014-final-0.2.4-candidate.v1') { throw 'Unexpected candidate evidence schema.' }
if ([string]$contract.schema -ne 'arvectum.proxy.apl-win-014-final-0.2.4-physical-contract.v1') { throw 'Unexpected physical contract schema.' }
if ([string]$candidate.product_version -ne '0.2.4' -or [string]$candidate.supported_predecessor_version -ne '0.2.3') {
    throw 'Candidate version/predecessor contract mismatch.'
}
if ((Normalize-GuidText $BasePolicyId) -ne (Normalize-GuidText $contract.base_policy_id)) {
    throw "BasePolicyId does not match sealed physical contract: $($contract.base_policy_id)"
}

$setupPath = Join-Path $CandidateDirectory ([string]$candidate.setup.filename)
$appPath = Join-Path $CandidateDirectory ([string]$candidate.application.filename)
$upgradeHelperPath = Join-Path $CandidateDirectory ([string]$candidate.upgrade_helper.filename)
$uninstallHelperPath = Join-Path $CandidateDirectory ([string]$candidate.uninstall_helper.filename)
$runnerPath = Join-Path $CandidateDirectory ([string]$candidate.physical_runner.filename)
$uninstallerPath = Join-Path (Join-Path $CandidateDirectory 'policy-material') ([string]$candidate.reference_uninstaller.filename)
$previousSetupPath = Join-Path $PreviousReleaseDirectory 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe'
$pyRuntimeEvidencePath = Join-Path $CandidateDirectory ([string]$contract.pyinstaller_runtime_evidence_filename)
$pyRuntimeRoot = Join-Path $CandidateDirectory ([string]$contract.pyinstaller_runtime_directory)

$expectedCandidateSetup = [string]$candidate.setup.sha256
$expectedCandidateApp = [string]$candidate.application.sha256
$expectedUpgradeHelper = [string]$candidate.upgrade_helper.sha256
$expectedUninstallHelper = [string]$candidate.uninstall_helper.sha256
$expectedRunner = [string]$candidate.physical_runner.sha256
$expectedUninstaller = [string]$candidate.reference_uninstaller.sha256
$expectedPreviousSetup = [string]$contract.predecessor.setup_sha256
$expectedRuntime = [string]$contract.inno_runtime_sha256

if ($expectedCandidateSetup -ne [string]$contract.candidate.setup_sha256) { throw 'Candidate Setup identity disagrees with physical contract.' }
if ($expectedCandidateApp -ne [string]$contract.candidate.application_sha256) { throw 'Candidate application identity disagrees with physical contract.' }
if ($expectedCandidateApp -ne [string]$contract.pyinstaller_runtime_source_application_sha256) { throw 'PyInstaller runtime source application disagrees with physical contract.' }
if ($expectedCandidateApp -ne [string]$candidate.pyinstaller_runtime_trust.source_application_sha256) { throw 'PyInstaller runtime source application disagrees with candidate evidence.' }
if ([string]$candidate.pyinstaller_runtime_trust.directory -ne [string]$contract.pyinstaller_runtime_directory) { throw 'PyInstaller runtime directory disagrees across sealed metadata.' }
if ([string]$candidate.pyinstaller_runtime_trust.evidence_filename -ne [string]$contract.pyinstaller_runtime_evidence_filename) { throw 'PyInstaller runtime evidence filename disagrees across sealed metadata.' }
if ([int]$candidate.pyinstaller_runtime_trust.binary_count -ne [int]$contract.pyinstaller_runtime_binary_count) { throw 'PyInstaller runtime binary count disagrees across sealed metadata.' }
if ([long]$candidate.pyinstaller_runtime_trust.total_size -ne [long]$contract.pyinstaller_runtime_total_size) { throw 'PyInstaller runtime total size disagrees across sealed metadata.' }
if ($expectedUninstaller -ne [string]$contract.candidate.uninstaller_sha256) { throw 'Candidate uninstaller identity disagrees with physical contract.' }
if ($expectedRunner -ne [string]$contract.candidate.runner_sha256) { throw 'Physical runner identity disagrees with physical contract.' }

Assert-ExactFile $setupPath $expectedCandidateSetup '0.2.4 Setup'
Assert-ExactFile $appPath $expectedCandidateApp '0.2.4 application'
Assert-ExactFile $upgradeHelperPath $expectedUpgradeHelper '0.2.4 upgrade helper'
Assert-ExactFile $uninstallHelperPath $expectedUninstallHelper '0.2.4 uninstall helper'
Assert-ExactFile $runnerPath $expectedRunner '0.2.4 physical runner'
Assert-ExactFile $uninstallerPath $expectedUninstaller '0.2.4 deterministic uninstaller'
Assert-ExactFile $previousSetupPath $expectedPreviousSetup 'canonical 0.2.3 Setup'
Assert-ExactFile $RuntimePath $expectedRuntime 'candidate-derived Inno Setup 6.7.1 runtime'

if (-not (Test-Path -LiteralPath $pyRuntimeEvidencePath -PathType Leaf)) { throw "PyInstaller native runtime evidence missing: $pyRuntimeEvidencePath" }
if (-not (Test-Path -LiteralPath $pyRuntimeRoot -PathType Container)) { throw "PyInstaller native runtime directory missing: $pyRuntimeRoot" }
$pyRuntimeEvidence = Get-Content -LiteralPath $pyRuntimeEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$pyRuntimeEvidence.schema -ne 'arvectum.proxy.apl-win-014-pyinstaller-native-runtime.v1') { throw 'Unexpected PyInstaller native runtime evidence schema.' }
if ([string]$pyRuntimeEvidence.result -ne 'PASS') { throw 'PyInstaller native runtime evidence is not PASS.' }
if ([string]$pyRuntimeEvidence.source_application_sha256 -ne $expectedCandidateApp) { throw 'PyInstaller native runtime evidence is not bound to the exact candidate application.' }
if ([int]$pyRuntimeEvidence.binary_count -ne [int]$contract.pyinstaller_runtime_binary_count) { throw 'PyInstaller native runtime evidence count disagrees with contract.' }
if ([long]$pyRuntimeEvidence.total_size -ne [long]$contract.pyinstaller_runtime_total_size) { throw 'PyInstaller native runtime evidence size disagrees with contract.' }

$actualPyRuntimeFiles = @(Get-ChildItem -LiteralPath $pyRuntimeRoot -File -Recurse)
if ($actualPyRuntimeFiles.Count -ne [int]$pyRuntimeEvidence.binary_count) {
    throw "PyInstaller native runtime directory contains $($actualPyRuntimeFiles.Count) files; expected $($pyRuntimeEvidence.binary_count)."
}
foreach ($requiredNative in @('python312.dll','ucrtbase.dll')) {
    $requiredMatches = @($actualPyRuntimeFiles | Where-Object { $_.Name -ieq $requiredNative })
    if ($requiredMatches.Count -lt 1) { throw "Required PyInstaller native runtime binary is missing: $requiredNative" }
}

$totalRuntimeSize = [long]0
foreach ($entry in @($pyRuntimeEvidence.entries)) {
    $relative = [string]$entry.path
    if (-not $relative) { throw 'PyInstaller native runtime evidence contains an empty path.' }
    if ($relative -match '^(?:[A-Za-z]:\\|\\\\|/)') { throw "PyInstaller runtime path must be candidate-relative: $relative" }
    if ($relative -match '(^|[\\/])\.\.([\\/]|$)') { throw "PyInstaller runtime path contains parent traversal: $relative" }
    $relativeWindows = $relative -replace '/', '\\'
    $source = Join-Path $pyRuntimeRoot $relativeWindows
    Assert-ExactFile $source ([string]$entry.sha256) "PyInstaller native runtime $relative"
    $item = Get-Item -LiteralPath $source
    if ([long]$item.Length -ne [long]$entry.size) { throw "PyInstaller native runtime size mismatch: $relative" }
    $totalRuntimeSize += [long]$entry.size
}
if ($totalRuntimeSize -ne [long]$pyRuntimeEvidence.total_size) { throw 'PyInstaller native runtime aggregate size mismatch.' }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$tempRoot = $null
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    $candidateTemp = Join-Path $env:TEMP ("ArvectumAplWin014Final024-$(Get-Random -Minimum 100000 -Maximum 999999)")
    if (-not (Test-Path -LiteralPath $candidateTemp)) {
        $tempRoot = $candidateTemp
        break
    }
}
if (-not $tempRoot) { throw 'Unable to allocate a unique temporary directory.' }
$scanRoot = Join-Path $tempRoot 'scan'
New-Item -ItemType Directory -Path $scanRoot -Force | Out-Null

try {
    Copy-ExactFile $previousSetupPath (Join-Path $scanRoot 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe') $expectedPreviousSetup 'canonical 0.2.3 Setup'
    Copy-ExactFile $setupPath (Join-Path $scanRoot 'Arvectum-Proxy-Launcher-0.2.4-windows-x64-setup.exe') $expectedCandidateSetup '0.2.4 Setup'
    Copy-ExactFile $appPath (Join-Path $scanRoot 'Arvectum Proxy Launcher.exe') $expectedCandidateApp '0.2.4 application'
    Copy-ExactFile $upgradeHelperPath (Join-Path $scanRoot 'upgrade_helper.ps1') $expectedUpgradeHelper '0.2.4 upgrade helper'
    Copy-ExactFile $uninstallHelperPath (Join-Path $scanRoot 'uninstall_helper.ps1') $expectedUninstallHelper '0.2.4 uninstall helper'
    Copy-ExactFile $runnerPath (Join-Path $scanRoot 'apl_win_014_final_0_2_4_physical.ps1') $expectedRunner '0.2.4 physical runner'
    Copy-ExactFile $uninstallerPath (Join-Path $scanRoot 'unins000.exe') $expectedUninstaller '0.2.4 deterministic uninstaller'
    Copy-ExactFile $RuntimePath (Join-Path $scanRoot 'inno-setup-6.7.1-candidate-runtime.exe') $expectedRuntime 'candidate-derived Inno Setup 6.7.1 runtime'

    $pyScanRoot = Join-Path $scanRoot 'pyinstaller-runtime'
    New-Item -ItemType Directory -Path $pyScanRoot -Force | Out-Null
    foreach ($entry in @($pyRuntimeEvidence.entries)) {
        $relative = [string]$entry.path
        $relativeWindows = $relative -replace '/', '\\'
        $source = Join-Path $pyRuntimeRoot $relativeWindows
        $destination = Join-Path $pyScanRoot $relativeWindows
        $destinationDirectory = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }
        Copy-ExactFile $source $destination ([string]$entry.sha256) "PyInstaller native runtime $relative"
    }

    $policyXml = Join-Path $OutputDirectory 'Arvectum-Proxy-Launcher-0.2.4-Final-Supplemental.xml'
    Write-Host '=== Generate exact-hash App Control supplemental policy ==='
    New-CIPolicy -MultiplePolicyFormat -ScanPath $scanRoot -UserPEs -NoShadowCopy -FilePath $policyXml -Level Hash | Out-Null

    $xmlText = Get-Content -LiteralPath $policyXml -Raw -Encoding UTF8
    if ($xmlText -match 'Disabled:Script Enforcement') { throw 'Generated policy disables script enforcement; refusing unsafe policy.' }
    foreach ($scriptName in @('upgrade_helper.ps1','uninstall_helper.ps1','apl_win_014_final_0_2_4_physical.ps1')) {
        if ($xmlText -notlike "*$scriptName*") { throw "Generated policy is missing exact script rule material for $scriptName." }
    }

    Set-CIPolicyIdInfo -FilePath $policyXml -ResetPolicyID -PolicyName 'Arvectum Proxy Launcher 0.2.4 Final Exact Hash' -SupplementsBasePolicyID $BasePolicyId | Out-Null
    Set-CIPolicyVersion -FilePath $policyXml -Version '0.2.4.0'
    $policyId = Get-PolicyIdFromXml $policyXml
    $policyCipName = "{$policyId}.cip"
    $policyCip = Join-Path $OutputDirectory $policyCipName
    ConvertFrom-CIPolicy -XmlFilePath $policyXml -BinaryFilePath $policyCip
    if (-not (Test-Path -LiteralPath $policyCip -PathType Leaf)) { throw 'ConfigCI did not create the binary supplemental policy.' }

    $files = @(
        [ordered]@{ role='predecessor_setup'; filename=(Split-Path -Leaf $previousSetupPath); sha256=$expectedPreviousSetup },
        [ordered]@{ role='candidate_setup'; filename=(Split-Path -Leaf $setupPath); sha256=$expectedCandidateSetup },
        [ordered]@{ role='candidate_application'; filename=(Split-Path -Leaf $appPath); sha256=$expectedCandidateApp },
        [ordered]@{ role='upgrade_helper'; filename=(Split-Path -Leaf $upgradeHelperPath); sha256=$expectedUpgradeHelper },
        [ordered]@{ role='uninstall_helper'; filename=(Split-Path -Leaf $uninstallHelperPath); sha256=$expectedUninstallHelper },
        [ordered]@{ role='physical_runner'; filename=(Split-Path -Leaf $runnerPath); sha256=$expectedRunner },
        [ordered]@{ role='candidate_uninstaller'; filename=(Split-Path -Leaf $uninstallerPath); sha256=$expectedUninstaller },
        [ordered]@{ role='inno_runtime'; filename=(Split-Path -Leaf $RuntimePath); sha256=$expectedRuntime }
    )
    foreach ($entry in @($pyRuntimeEvidence.entries)) {
        $files += [ordered]@{
            role = 'pyinstaller_runtime_binary'
            filename = [string]$entry.path
            sha256 = [string]$entry.sha256
        }
    }

    $manifest = [ordered]@{
        schema = 'arvectum.proxy.apl-win-014-final-0.2.4-app-control-trust.v1'
        task = 'APL-WIN-014'
        created_utc = Get-UtcTimestamp
        candidate_source_commit = [string]$candidate.candidate_source_commit
        candidate_version = '0.2.4'
        predecessor_version = '0.2.3'
        base_policy_id = (Normalize-GuidText $BasePolicyId)
        supplemental_policy_id = (Normalize-GuidText $policyId)
        supplemental_policy_xml = (Split-Path -Leaf $policyXml)
        supplemental_policy_xml_sha256 = Get-Sha256 $policyXml
        supplemental_policy_cip = (Split-Path -Leaf $policyCip)
        supplemental_policy_cip_sha256 = Get-Sha256 $policyCip
        rule_level = 'Hash'
        pyinstaller_runtime_source_application_sha256 = [string]$pyRuntimeEvidence.source_application_sha256
        pyinstaller_runtime_binary_count = [int]$pyRuntimeEvidence.binary_count
        pyinstaller_runtime_total_size = [long]$pyRuntimeEvidence.total_size
        script_enforcement_disabled = $false
        exact_files = $files
        policy_deployed = $false
        security_controls_modified = $false
        result = 'PASS'
    }
    $manifestPath = Join-Path $OutputDirectory 'trust-pack.json'
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $deployPath = Join-Path $OutputDirectory 'POLICY_TO_DEPLOY.txt'
    @"
APL-WIN-014 FINAL 0.2.4 SUPPLEMENTAL POLICY
===========================================
Result: PASS
Base PolicyID: $($manifest.base_policy_id)
Supplemental PolicyID: $($manifest.supplemental_policy_id)
CIP: $policyCip
CIP SHA256: $($manifest.supplemental_policy_cip_sha256)
Candidate source commit: $($manifest.candidate_source_commit)
PyInstaller exact native binaries: $($manifest.pyinstaller_runtime_binary_count)

This helper DID NOT deploy policy and DID NOT modify Windows protection.
On the dedicated ARVECTUM-DEMO lab host, deploy only through the approved App Control path.
Standalone lab primitive:
  & `$env:SystemRoot\System32\CiTool.exe --update-policy '$policyCip'

Then verify with:
  & `$env:SystemRoot\System32\CiTool.exe -lp -json
Do not continue unless the canonical base policy and this supplemental are on-disk, authorized, and enforced.
"@ | Set-Content -LiteralPath $deployPath -Encoding UTF8

    $sums = Get-ChildItem -LiteralPath $OutputDirectory -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | Sort-Object Name | ForEach-Object {
        "$(Get-Sha256 $_.FullName)  $($_.Name)"
    }
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Value $sums -Encoding ASCII

    Write-Host ''
    Write-Host 'APL-WIN-014 final 0.2.4 App Control trust authoring: PASS'
    Write-Host "Supplemental PolicyID: $($manifest.supplemental_policy_id)"
    Write-Host "CIP: $policyCip"
    Write-Host "Trust manifest: $manifestPath"
    Write-Host "PyInstaller exact native binaries: $($manifest.pyinstaller_runtime_binary_count)"
    Write-Host 'Policy deployed: NO'
    Write-Host 'Security controls modified: NO'
}
finally {
    if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
