<#
.SYNOPSIS
    Author an exact-hash App Control supplemental policy for the APL-WIN-014
    PowerShell acceptance harness while the host PowerShell is constrained by UMCI.
.DESCRIPTION
    This script is intentionally compatible with PowerShell ConstrainedLanguage.
    It runs before the final harness is trusted, verifies the canonical enforced lab
    base policy, stages only the exact PowerShell scripts required by the final physical
    acceptance flow, and authors a supplemental App Control policy with script rules.

    The script NEVER deploys/removes policy, NEVER enables Audit Mode, NEVER disables
    Script Enforcement, and NEVER authorizes python.exe or another general interpreter.
    Deployment of the emitted .cip remains an explicit lab-owner action.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = '',
    [string]$ReleaseDirectory = 'C:\Arvectum\Releases\0.2.3-russian-production',
    [string]$OutputDirectory = 'C:\Arvectum\Evidence\APL-WIN-014\harness-script-trust'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedBasePolicyId = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$ExpectedBaseFriendlyName = 'Arvectum APL-WIN-014 Lab Base'
$PolicyFriendlyName = 'Arvectum APL-WIN-014 Final Harness Script Trust'
$PolicyVersion = '0.0.14.1'
$ExpectedSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'

function Get-ClmSha256 {
    [CmdletBinding()]
    param([string]$Path = '')
    if ($Path -eq '' -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "SHA256 input is missing: $Path"
    }
    $certUtil = Join-Path $env:SystemRoot 'System32\certutil.exe'
    if (-not (Test-Path -LiteralPath $certUtil -PathType Leaf)) { throw 'certutil.exe is required.' }
    $output = & $certUtil -hashfile $Path SHA256 2>$null
    if ($LASTEXITCODE -ne 0) { throw "certutil SHA256 failed for: $Path" }
    $matchesFound = @($output | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '\s','' })
    if ($matchesFound.Count -ne 1) { throw "Unable to parse SHA256 for: $Path" }
    return $matchesFound[0]
}

function Convert-ClmGuidText {
    [CmdletBinding()]
    param([string]$Value = '')
    if ($Value -eq '') { return '' }
    $normalized = $Value -replace '^\{','' -replace '\}$',''
    if ($normalized -notmatch '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') {
        throw "Malformed policy GUID: $Value"
    }
    return $normalized
}

function Get-ClmPolicyIdFromXml {
    [CmdletBinding()]
    param([string]$Path = '')
    $ids = @()
    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ($line -match '<PolicyID>\s*([^<\s]+)\s*</PolicyID>') { $ids += $matches[1] }
    }
    if ($ids.Count -ne 1) { throw 'Generated harness policy does not contain exactly one PolicyID.' }
    return (Convert-ClmGuidText $ids[0])
}

function Assert-ClmBasePolicy {
    [CmdletBinding()]
    param()
    $ciTool = Join-Path $env:SystemRoot 'System32\CiTool.exe'
    if (-not (Test-Path -LiteralPath $ciTool -PathType Leaf)) { throw 'CiTool.exe is required.' }
    $result = & $ciTool -lp -json 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'CiTool -lp -json failed.' }
    if ($result.OperationResult -ne 0) { throw 'CiTool returned a non-zero OperationResult.' }
    $expected = Convert-ClmGuidText $ExpectedBasePolicyId
    $base = @($result.Policies | Where-Object { (Convert-ClmGuidText "$($_.PolicyID)") -ieq $expected })
    if ($base.Count -ne 1) { throw "Canonical Lab Base is not uniquely active; found $($base.Count)." }
    if ((Convert-ClmGuidText "$($base[0].BasePolicyID)") -ine $expected) { throw 'Canonical Lab Base BasePolicyID self-reference mismatch.' }
    if ($base[0].FriendlyName -ne $ExpectedBaseFriendlyName) { throw "Canonical Lab Base FriendlyName mismatch: $($base[0].FriendlyName)" }
    if ($base[0].IsOnDisk -ne $true -or $base[0].IsEnforced -ne $true -or $base[0].IsAuthorized -ne $true) {
        throw 'Canonical Lab Base is not OnDisk/Enforced/Authorized.'
    }
    $options = @($base[0].PolicyOptions)
    if ($options -contains 'Enabled:Audit Mode') { throw 'Canonical Lab Base is in Audit Mode; failing closed.' }
    if ($options -notcontains 'Enabled:Allow Supplemental Policies') { throw 'Canonical Lab Base does not allow supplemental policies.' }
}

if ($env:OS -ne 'Windows_NT') { throw 'APL-WIN-014 harness trust bootstrap must run on Windows.' }
if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'Windows PowerShell 5.1 or later is required.' }

$net = Join-Path $env:SystemRoot 'System32\net.exe'
& $net session *> $null
if ($LASTEXITCODE -ne 0) { throw 'Elevated Administrator PowerShell is required.' }

$languageMode = "$($ExecutionContext.SessionState.LanguageMode)"
Write-Host "PowerShell language mode before harness trust: $languageMode"
if ($languageMode -ne 'ConstrainedLanguage' -and $languageMode -ne 'FullLanguage') {
    throw "Unsupported PowerShell language mode: $languageMode"
}

if ($RepositoryRoot -eq '') { $RepositoryRoot = Split-Path $PSScriptRoot -Parent }
if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) { throw "RepositoryRoot is missing: $RepositoryRoot" }
if (-not (Test-Path -LiteralPath $ReleaseDirectory -PathType Container)) { throw "Production release directory is missing: $ReleaseDirectory" }
if (Test-Path -LiteralPath $OutputDirectory) { throw "OutputDirectory already exists; refusing overwrite: $OutputDirectory" }

$setup = Join-Path $ReleaseDirectory 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe'
$releaseVerifier = Join-Path $ReleaseDirectory 'verify_russian_release.ps1'
if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw "Canonical production Setup is missing: $setup" }
if ((Get-ClmSha256 $setup) -ine $ExpectedSetupSha256) { throw 'Production Setup SHA256 mismatch; refusing to trust harness against another release.' }
if (-not (Test-Path -LiteralPath $releaseVerifier -PathType Leaf)) { throw "Russian release verifier is missing: $releaseVerifier" }

foreach ($commandName in @('New-CIPolicy','Set-CIPolicyIdInfo','Set-CIPolicyVersion','ConvertFrom-CIPolicy')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) { throw "Required ConfigCI command is unavailable: $commandName" }
}

Assert-ClmBasePolicy

$repoScripts = @(
    'windows_app_control_prepare_final_stand.ps1',
    'windows_app_control_run_final_stand.ps1',
    'windows_app_control_recover_0_2_2_baseline.ps1',
    'windows_app_control_legacy_baseline_trust_pack.ps1',
    'windows_app_control_prepare_production_runtime_trust.ps1',
    'windows_app_control_enterprise_trust_pack.ps1',
    'windows_app_control_inno_runtime_material.ps1',
    'windows_app_control_verify_runtime_trust_pack.ps1',
    'windows_app_control_local_gate_complete.ps1',
    'windows_app_control_enforced_acceptance.ps1',
    'windows_app_control_preverified_release.ps1',
    'windows_app_control_harness_language_probe.ps1'
)

$toolsRoot = Join-Path $RepositoryRoot 'tools'
$sourceCommit = ''
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($git) {
    $headOutput = & $git.Source -C $RepositoryRoot rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0) {
        $heads = @($headOutput | Where-Object { $_ -match '^[0-9A-Fa-f]{40}$' })
        if ($heads.Count -eq 1) { $sourceCommit = $heads[0] }
    }
    foreach ($name in $repoScripts) {
        $status = & $git.Source -C $RepositoryRoot status --porcelain -- (Join-Path 'tools' $name) 2>$null
        if ($LASTEXITCODE -ne 0) { throw "Unable to validate Git status for harness script: $name" }
        if (@($status).Count -ne 0) { throw "Harness script has local Git changes; refusing to authorize it: $name" }
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$scanRoot = Join-Path $OutputDirectory 'script-scan-root'
New-Item -ItemType Directory -Path $scanRoot -Force | Out-Null

$inventory = @()
foreach ($name in $repoScripts) {
    $source = Join-Path $toolsRoot $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required harness script is missing: $source" }
    $destination = Join-Path $scanRoot $name
    Copy-Item -LiteralPath $source -Destination $destination
    $inventory += [ordered]@{ filename=$name; source=$source; sha256=(Get-ClmSha256 $source) }
}

$releaseVerifierName = 'verify_russian_release.ps1'
$releaseVerifierStaged = Join-Path $scanRoot $releaseVerifierName
Copy-Item -LiteralPath $releaseVerifier -Destination $releaseVerifierStaged
$inventory += [ordered]@{ filename=$releaseVerifierName; source=$releaseVerifier; sha256=(Get-ClmSha256 $releaseVerifier) }

$policyXml = Join-Path $OutputDirectory 'Arvectum-APL-WIN-014-Final-Harness-Script-Trust.xml'
Write-Host 'Authoring exact-hash script supplemental policy...'
# Deliberately omit -NoScript: this supplemental exists solely to authorize the exact
# acceptance-harness script bytes. No interpreter executable is staged or authorized.
New-CIPolicy -MultiplePolicyFormat -ScanPath $scanRoot -UserPEs -NoShadowCopy -FilePath $policyXml -Level Hash | Out-Null
Set-CIPolicyIdInfo -FilePath $policyXml -ResetPolicyID -PolicyName $PolicyFriendlyName -SupplementsBasePolicyID $ExpectedBasePolicyId | Out-Null
Set-CIPolicyVersion -FilePath $policyXml -Version $PolicyVersion

$policyId = Get-ClmPolicyIdFromXml $policyXml
$baseIds = @()
foreach ($line in @(Get-Content -LiteralPath $policyXml -Encoding UTF8)) {
    if ($line -match '<BasePolicyID>\s*([^<\s]+)\s*</BasePolicyID>') { $baseIds += Convert-ClmGuidText $matches[1] }
}
if ($baseIds.Count -ne 1 -or $baseIds[0] -ine (Convert-ClmGuidText $ExpectedBasePolicyId)) { throw 'Generated harness supplemental targets another base policy.' }
if ($policyId -ieq (Convert-ClmGuidText $ExpectedBasePolicyId)) { throw 'Harness supplemental PolicyID must differ from the base PolicyID.' }

$xmlLines = @(Get-Content -LiteralPath $policyXml -Encoding UTF8)
foreach ($entry in $inventory) {
    if (@($xmlLines | Where-Object { $_ -like "*$($entry.filename)*" }).Count -eq 0) {
        throw "Generated App Control XML contains no rule evidence for required script: $($entry.filename)"
    }
}
if (@($xmlLines | Where-Object { $_ -match '<SigningScenario\b[^>]*\bValue="12"' }).Count -eq 0) {
    throw 'Generated App Control XML has no user-mode SigningScenario 12.'
}

$policyCip = Join-Path $OutputDirectory ("{" + $policyId + "}.cip")
ConvertFrom-CIPolicy -XmlFilePath $policyXml -BinaryFilePath $policyCip
if (-not (Test-Path -LiteralPath $policyCip -PathType Leaf)) { throw 'ConfigCI did not create the harness supplemental .cip.' }

$state = [ordered]@{
    schema='arvectum.proxy.apl-win-014-harness-script-trust.v1'
    task='APL-WIN-014'
    created_utc=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    host=$env:COMPUTERNAME
    source_repository='arvectum2/proxy-launcher'
    source_commit=$sourceCommit
    pre_authoring_language_mode=$languageMode
    base_policy_id=$ExpectedBasePolicyId
    supplemental_policy_id=$policyId
    supplemental_policy_friendly_name=$PolicyFriendlyName
    supplemental_policy_version=$PolicyVersion
    supplemental_policy_xml=$policyXml
    supplemental_policy_xml_sha256=(Get-ClmSha256 $policyXml)
    supplemental_policy_cip=$policyCip
    supplemental_policy_cip_sha256=(Get-ClmSha256 $policyCip)
    authorized_scripts=$inventory
    python_authorized=$false
    general_interpreter_authorized=$false
    policy_deployment='NOT PERFORMED'
    security_controls_weakened=$false
    result='PREPARED'
}
$statePath = Join-Path $OutputDirectory 'harness-script-trust.json'
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8

$handoff = @(
    'APL-WIN-014 FINAL HARNESS SCRIPT TRUST',
    '========================================',
    '',
    "Base PolicyID: $ExpectedBasePolicyId",
    "Harness supplemental PolicyID: $policyId",
    "CIP: $policyCip",
    "CIP SHA256: $($state.supplemental_policy_cip_sha256)",
    '',
    'This policy trusts only the exact staged PowerShell harness script bytes.',
    'It does NOT authorize python.exe or any other general interpreter.',
    'It does NOT deploy itself and does NOT weaken App Control.',
    '',
    'Explicit lab-owner deployment command:',
    "CiTool.exe --update-policy `"$policyCip`"",
    '',
    'After deployment, CLOSE this PowerShell window and open a NEW elevated Windows PowerShell 5.1.',
    'Then run: .\tools\windows_app_control_harness_language_probe.ps1'
)
$handoffPath = Join-Path $OutputDirectory 'POLICY_TO_DEPLOY.txt'
Set-Content -LiteralPath $handoffPath -Value $handoff -Encoding UTF8

Remove-Item -LiteralPath $scanRoot -Recurse -Force

Write-Host ''
Write-Host 'APL-WIN-014 harness script trust bootstrap: PREPARED'
Write-Host "Language mode: $languageMode"
Write-Host "Policy ID: $policyId"
Write-Host "Policy CIP: $policyCip"
Write-Host "State: $statePath"
Write-Host "Deployment handoff: $handoffPath"
Write-Host 'Policy deployment: NOT PERFORMED'
Write-Host 'Security weakening: NO'
Write-Host 'General interpreter trust: NO'
