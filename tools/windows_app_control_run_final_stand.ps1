<#
.SYNOPSIS
    Execute the canonical APL-WIN-014 physical gate from a prepared stand-state manifest.
.DESCRIPTION
    Run only after the two prepared supplemental .cip policies have been deployed through
    the approved lab App Control management path. The wrapper verifies policy activation,
    re-verifies the exact current reference installation, cleans only that governed
    Arvectum reference state, and then invokes windows_app_control_local_gate_complete.ps1.

    It never deploys/removes App Control policy and never weakens Smart App Control,
    Defender, App Control for Business, or policy options.
#>
[CmdletBinding()]
param(
    [string]$StatePath = 'C:\Arvectum\Evidence\APL-WIN-014\final-stand\stand-state.json',
    [string]$SigningEvidencePath = '',
    [switch]$IsolatedAcceptanceEnvironment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedSchema = 'arvectum.proxy.apl-win-014-final-stand-state.v1'
$ExpectedBasePolicyId = [Guid]'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$ExpectedSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
$ExpectedAppSha256 = 'f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a'
$ExpectedRuntimeSha256 = 'b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8'
$PacUrl = 'http://127.0.0.1:8082/proxy.pac'
$AppKeyName = '{6A5A0706-4015-4EAF-BFA1-25EF435C9E1B}_is1'
$UserUninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppKeyName"
$LegacyUninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ArvectumProxyLauncher'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Normalize-GuidText([object]$Value) {
    if ($null -eq $Value) { return '' }
    return ([Guid](([string]$Value).Trim().Trim('{}'))).ToString('D').ToLowerInvariant()
}

function Get-CiPolicies {
    $ciTool = Join-Path $env:SystemRoot 'System32\CiTool.exe'
    if (-not (Test-Path -LiteralPath $ciTool -PathType Leaf)) { throw 'CiTool.exe is required.' }
    $raw = & $ciTool -lp -json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "CiTool -lp -json failed: $($raw -join ' ')" }
    $parsed = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
    $items = if ($parsed.PSObject.Properties['Policies']) { @($parsed.Policies) } else { @($parsed) }
    return @($items | ForEach-Object {
        [pscustomobject]@{
            policy_id = Normalize-GuidText $_.PolicyID
            base_policy_id = Normalize-GuidText $_.BasePolicyID
            is_enforced = [bool]$_.IsEnforced
            is_on_disk = [bool]$_.IsOnDisk
            is_authorized = $(if ($_.PSObject.Properties['IsAuthorized']) { [bool]$_.IsAuthorized } else { $null })
            policy_options = @($_.PolicyOptions)
        }
    })
}

function Assert-SupplementalActive([object[]]$Policies, [Guid]$PolicyId, [Guid]$BaseId, [string]$Label) {
    $policyText = Normalize-GuidText $PolicyId
    $baseText = Normalize-GuidText $BaseId
    $matches = @($Policies | Where-Object { $_.policy_id -eq $policyText })
    if ($matches.Count -ne 1 -or -not $matches[0].is_on_disk) { throw "Prepared $Label supplemental policy is not active/on-disk." }
    if ($matches[0].is_authorized -eq $false) { throw "Prepared $Label supplemental policy is not authorized." }
    if ($matches[0].base_policy_id -and $matches[0].base_policy_id -ne $baseText) { throw "Prepared $Label supplemental policy targets another base policy." }
}

function Assert-PreparedPoliciesActive([object[]]$Policies, [Guid]$BaseId, [Guid]$BaselineId, [Guid]$CurrentId) {
    $baseText = Normalize-GuidText $BaseId
    $base = @($Policies | Where-Object { $_.policy_id -eq $baseText })
    if ($base.Count -ne 1 -or -not $base[0].is_enforced -or -not $base[0].is_on_disk) { throw 'Canonical base policy is not active and enforced.' }
    if (@($base[0].policy_options) -contains 'Enabled:Audit Mode') { throw 'Canonical base policy is in Audit Mode.' }
    if (@($base[0].policy_options) -notcontains 'Enabled:Allow Supplemental Policies') { throw 'Canonical base policy does not allow supplemental policies.' }
    Assert-SupplementalActive -Policies $Policies -PolicyId $BaselineId -BaseId $BaseId -Label 'baseline'
    Assert-SupplementalActive -Policies $Policies -PolicyId $CurrentId -BaseId $BaseId -Label 'current'
}

function Get-ExactLauncherProcesses([string]$ExePath) {
    $full = [IO.Path]::GetFullPath($ExePath)
    return @(Get-CimInstance Win32_Process -Filter "Name='Arvectum Proxy Launcher.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -and ([IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq $full)
    })
}

function Assert-ExactReferenceTree([string]$InstalledRoot, [object]$CurrentTrust) {
    if (-not (Test-Path -LiteralPath $InstalledRoot -PathType Container)) { throw 'Prepared current reference installation is missing.' }
    $records = @($CurrentTrust.reference_files)
    if ($records.Count -eq 0) { throw 'Current ReferenceFullHash manifest has no reference file inventory.' }

    $expected = @{}
    foreach ($record in $records) {
        $relative = ([string]$record.relative_path).TrimStart('\')
        if ([string]::IsNullOrWhiteSpace($relative) -or $expected.ContainsKey($relative.ToLowerInvariant())) { throw 'Current reference inventory contains an empty/duplicate path.' }
        $expected[$relative.ToLowerInvariant()] = $record
    }

    $liveFiles = @(Get-ChildItem -LiteralPath $InstalledRoot -File -Recurse -Force)
    if ($liveFiles.Count -ne $records.Count) { throw 'Live reference installation file count drifted after trust-pack authoring.' }
    foreach ($file in $liveFiles) {
        $relative = $file.FullName.Substring($InstalledRoot.Length).TrimStart('\')
        $key = $relative.ToLowerInvariant()
        if (-not $expected.ContainsKey($key)) { throw "Live reference installation contains an unverified file: $relative" }
        $record = $expected[$key]
        if ([long]$file.Length -ne [long]$record.size -or (Get-Sha256 $file.FullName) -ne ([string]$record.sha256).ToLowerInvariant()) {
            throw "Live reference installation changed after trust-pack authoring: $relative"
        }
    }

    $app = Join-Path $InstalledRoot 'Arvectum Proxy Launcher.exe'
    $repair = Join-Path $InstalledRoot 'Arvectum Proxy Launcher Repair.exe'
    $uninstaller = Join-Path $InstalledRoot 'unins000.exe'
    foreach ($required in @($app,$repair,$uninstaller)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required exact reference lifecycle file is missing: $required" }
    }
    if ((Get-Sha256 $app) -ne $ExpectedAppSha256) { throw 'Reference application EXE is not the exact production binary.' }
    if ((Get-Sha256 $repair) -ne $ExpectedSetupSha256) { throw 'Reference repair Setup is not the exact production installer.' }
    return [pscustomobject]@{ app=$app; repair=$repair; uninstaller=$uninstaller; verified_records=$records }
}

function Assert-ResidualReferenceTreeStillKnown([string]$InstalledRoot, [object[]]$VerifiedRecords) {
    if (-not (Test-Path -LiteralPath $InstalledRoot -PathType Container)) { return }
    $known = @{}
    foreach ($record in $VerifiedRecords) { $known[([string]$record.relative_path).TrimStart('\').ToLowerInvariant()] = $record }
    foreach ($file in @(Get-ChildItem -LiteralPath $InstalledRoot -File -Recurse -Force)) {
        $relative = $file.FullName.Substring($InstalledRoot.Length).TrimStart('\')
        $key = $relative.ToLowerInvariant()
        if (-not $known.ContainsKey($key)) { throw "Uninstaller left an unknown file; refusing cleanup: $relative" }
        $record = $known[$key]
        if ([long]$file.Length -ne [long]$record.size -or (Get-Sha256 $file.FullName) -ne ([string]$record.sha256).ToLowerInvariant()) {
            throw "Uninstaller left a changed file; refusing cleanup: $relative"
        }
    }
}

function Clean-ExactCurrentReference([string]$InstalledRoot, [object]$Reference) {
    $stateRoot = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
    $needsRollback = (Test-Path -LiteralPath $stateRoot) -or (Test-Path -LiteralPath $UserUninstallKey) -or (@(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue).Count -gt 0)
    try {
        $inet = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
        if ($inet -and $inet.PSObject.Properties['AutoConfigURL'] -and [string]$inet.AutoConfigURL -eq $PacUrl) { $needsRollback = $true }
    } catch {}

    if ($needsRollback) {
        $rollback = Start-Process -FilePath $Reference.app -ArgumentList @('--rollback') -PassThru
        if (-not $rollback.WaitForExit(20000)) { throw 'Exact production launcher --rollback did not return before timeout.' }
        if ($rollback.ExitCode -ne 0) { throw "Exact production launcher --rollback failed with exit code $($rollback.ExitCode)." }
    }

    foreach ($process in @(Get-ExactLauncherProcesses $Reference.app)) {
        Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
    }

    $uninstallLog = Join-Path (Split-Path $StatePath -Parent) 'reference-cleanup-uninstall.log'
    $uninstall = Start-Process -FilePath $Reference.uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/LOG=$uninstallLog")) -PassThru -Wait
    if ($uninstall.ExitCode -ne 0) { throw "Exact reference uninstaller failed with exit code $($uninstall.ExitCode)." }

    Assert-ResidualReferenceTreeStillKnown -InstalledRoot $InstalledRoot -VerifiedRecords $Reference.verified_records
    if (Test-Path -LiteralPath $InstalledRoot -PathType Container) { Remove-Item -LiteralPath $InstalledRoot -Recurse -Force }
    if (Test-Path -LiteralPath $stateRoot) { Remove-Item -LiteralPath $stateRoot -Recurse -Force }

    $currentKeyRemains = Test-Path -LiteralPath $UserUninstallKey
    $legacyKeyRemains = Test-Path -LiteralPath $LegacyUninstallKey
    if ($currentKeyRemains -or $legacyKeyRemains) { throw 'Governed Arvectum uninstall registration remains after exact reference cleanup.' }
    if (@(Get-ExactLauncherProcesses $Reference.app).Count -gt 0) { throw 'Exact launcher process remains after reference cleanup.' }
    if (@(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue).Count -gt 0) { throw 'TCP 8082 remains occupied after reference cleanup.' }
}

if (-not $IsolatedAcceptanceEnvironment) { throw 'SAFETY BLOCK: final stand execution is allowed only on the dedicated/isolated Windows 11 acceptance host.' }
if ($env:OS -ne 'Windows_NT') { throw 'Final stand execution must run on Windows.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Elevated Administrator PowerShell is required.' }
$os = Get-CimInstance Win32_OperatingSystem
if (([Version]([string]$os.Version)).Build -lt 22000) { throw 'Windows 11 is required for the physical acceptance stand.' }

$StatePath = (Resolve-Path -LiteralPath $StatePath).Path
$state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$state.schema -ne $ExpectedSchema -or [string]$state.result -ne 'PREPARED') { throw 'Stand state is not a prepared canonical APL-WIN-014 manifest.' }
$basePolicyId = [Guid]([string]$state.base_policy_id)
if ($basePolicyId -ne $ExpectedBasePolicyId) { throw 'Stand state targets another base policy.' }
$baselinePolicyId = [Guid]([string]$state.baseline.supplemental_policy_id)
$currentPolicyId = [Guid]([string]$state.current.supplemental_policy_id)

$baselineTrustDir = (Resolve-Path -LiteralPath ([string]$state.baseline.trust_pack_directory)).Path
$currentTrustDir = (Resolve-Path -LiteralPath ([string]$state.current.trust_pack_directory)).Path
$baselineManifestPath = (Resolve-Path -LiteralPath ([string]$state.baseline.manifest_path)).Path
$releaseDirectory = (Resolve-Path -LiteralPath ([string]$state.release_directory)).Path
$installedRoot = (Resolve-Path -LiteralPath ([string]$state.installed_reference_root)).Path
$canonicalInstalledRoot = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ArvectumProxyLauncher'))
if ([IO.Path]::GetFullPath($installedRoot) -ine $canonicalInstalledRoot) { throw 'Refusing cleanup outside the canonical Documents\ArvectumProxyLauncher reference root.' }

$baselineTrust = Get-Content -LiteralPath (Join-Path $baselineTrustDir 'trust-pack.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$currentTrust = Get-Content -LiteralPath (Join-Path $currentTrustDir 'trust-pack.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$baselineTrustId = Normalize-GuidText $baselineTrust.supplemental_policy_id
$currentTrustId = Normalize-GuidText $currentTrust.supplemental_policy_id
if ([string]$baselineTrust.result -ne 'PASS' -or $baselineTrustId -ne (Normalize-GuidText $baselinePolicyId)) { throw 'Baseline trust-pack identity drifted from stand state.' }
if ([string]$currentTrust.result -ne 'PASS' -or [string]$currentTrust.mode -ne 'ReferenceFullHash' -or $currentTrustId -ne (Normalize-GuidText $currentPolicyId)) { throw 'Current trust-pack identity drifted from stand state.' }
if ((Normalize-GuidText $baselineTrust.base_policy_id) -ne (Normalize-GuidText $basePolicyId) -or (Normalize-GuidText $currentTrust.base_policy_id) -ne (Normalize-GuidText $basePolicyId)) { throw 'Prepared trust packs do not target the canonical base policy.' }
if (([string]$currentTrust.release.installer_sha256).ToLowerInvariant() -ne $ExpectedSetupSha256 -or ([string]$currentTrust.release.application_exe_sha256).ToLowerInvariant() -ne $ExpectedAppSha256 -or ([string]$currentTrust.inno_runtime.sha256).ToLowerInvariant() -ne $ExpectedRuntimeSha256) { throw 'Current trust pack no longer binds the exact production identities.' }

$baselineCip = (Resolve-Path -LiteralPath ([string]$state.baseline.supplemental_policy_cip)).Path
$currentCip = (Resolve-Path -LiteralPath ([string]$state.current.supplemental_policy_cip)).Path
if ((Get-Sha256 $baselineCip) -ne ([string]$state.baseline.supplemental_policy_cip_sha256).ToLowerInvariant()) { throw 'Baseline supplemental CIP hash drifted from stand state.' }
if ((Get-Sha256 $currentCip) -ne ([string]$state.current.supplemental_policy_cip_sha256).ToLowerInvariant()) { throw 'Current supplemental CIP hash drifted from stand state.' }

$setup = Join-Path $releaseDirectory 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe'
if (-not (Test-Path -LiteralPath $setup -PathType Leaf) -or (Get-Sha256 $setup) -ne $ExpectedSetupSha256) { throw 'Canonical production Setup is missing or changed.' }

$policies = @(Get-CiPolicies)
Assert-PreparedPoliciesActive -Policies $policies -BaseId $basePolicyId -BaselineId $baselinePolicyId -CurrentId $currentPolicyId

Write-Host '=== Exact reference identity verification before cleanup ==='
$reference = Assert-ExactReferenceTree -InstalledRoot $installedRoot -CurrentTrust $currentTrust
Write-Host 'Exact current reference tree: PASS'

Write-Host '=== Clean only governed current reference state ==='
Clean-ExactCurrentReference -InstalledRoot $installedRoot -Reference $reference
Write-Host 'Governed current reference cleanup: PASS'

$finalGate = Join-Path $PSScriptRoot 'windows_app_control_local_gate_complete.ps1'
if (-not (Test-Path -LiteralPath $finalGate -PathType Leaf)) { throw 'Canonical final gate script is missing.' }
$finalEvidenceDir = [string]$state.final_evidence_directory
New-Item -ItemType Directory -Path $finalEvidenceDir -Force | Out-Null

$gateArgs = @{
    BasePolicyId = $basePolicyId
    BaselineSupplementalPolicyId = $baselinePolicyId
    BaselineManifestPath = $baselineManifestPath
    BaselineTrustPackDirectory = $baselineTrustDir
    ReleaseDirectory = $releaseDirectory
    TrustPackDirectory = $currentTrustDir
    EvidenceDirectory = $finalEvidenceDir
    IsolatedAcceptanceEnvironment = $true
}
if ($SigningEvidencePath) { $gateArgs.SigningEvidencePath = $SigningEvidencePath }

Write-Host '=== Canonical APL-WIN-014 final physical gate ==='
& $finalGate @gateArgs

$finalResultPath = Join-Path $finalEvidenceDir 'apl-win-014-final-result.json'
if (-not (Test-Path -LiteralPath $finalResultPath -PathType Leaf)) { throw 'Canonical final result evidence is missing.' }
$final = Get-Content -LiteralPath $finalResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$final.result -ne 'PASS' -or [string]$final.runtime_trust_gate -ne 'PASS' -or [string]$final.upgrade_gate -ne 'PASS' -or [string]$final.current_release_gate -ne 'PASS') {
    throw 'Canonical final evidence is not an all-subgate PASS.'
}

Write-Host ''
Write-Host 'APL-WIN-014 final physical stand orchestration: PASS'
Write-Host "Final evidence: $finalResultPath"
Write-Host 'Policy deployment/removal by this wrapper: NONE'
Write-Host 'Security-control weakening by this wrapper: NONE'
