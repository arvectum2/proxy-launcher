<#
.SYNOPSIS
    Focused physical APL-WIN-014 acceptance for final 0.2.4 candidate.
.DESCRIPTION
    Runs only the remaining physical proof on the dedicated ARVECTUM-DEMO host:
      - exact sealed 0.2.3 predecessor -> exact 0.2.4 upgrade;
      - exact installed 0.2.4 identity;
      - start + PAC + WinINET;
      - rollback;
      - repair;
      - uninstall;
      - zero Arvectum-related Code Integrity 3077 blocks;
      - base and candidate supplemental App Control policies remain enforced/authorized.

    This script never deploys/removes policy and never weakens Windows protection.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$CandidateDirectory,
    [Parameter(Mandatory = $true)] [Guid]$BasePolicyId,
    [Parameter(Mandatory = $true)] [Guid]$CandidateSupplementalPolicyId,
    [string]$PreviousReleaseDirectory = 'C:\Arvectum\Releases\0.2.3-russian-production',
    [string]$EvidenceDirectory = 'C:\Arvectum\Evidence\APL-WIN-014\final-0.2.4',
    [switch]$IsolatedAcceptanceEnvironment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedPreviousSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
$ExpectedPreviousApplicationSha256 = 'f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a'
$PacUrl = 'http://127.0.0.1:8082/proxy.pac'
$AppKeyName = '{6A5A0706-4015-4EAF-BFA1-25EF435C9E1B}_is1'
$UserUninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppKeyName"

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Normalize-GuidText([object]$Value) {
    if ($null -eq $Value) { return '' }
    $text = ([string]$Value).Trim().Trim('{}')
    try { return ([Guid]$text).ToString('D').ToLowerInvariant() } catch { return $text.ToLowerInvariant() }
}

function Get-CiToolPath {
    $path = Join-Path $env:SystemRoot 'System32\CiTool.exe'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'CiTool.exe is required.' }
    return $path
}

function Get-AppControlPolicies([string]$CiTool) {
    $raw = & $CiTool -lp -json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "CiTool -lp -json failed: $($raw -join ' ')" }
    $parsed = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
    $items = if ($parsed.PSObject.Properties['Policies']) { @($parsed.Policies) } else { @($parsed) }
    foreach ($p in $items) {
        [pscustomobject]@{
            policy_id = Normalize-GuidText $p.PolicyID
            base_policy_id = Normalize-GuidText $p.BasePolicyID
            friendly_name = [string]$p.FriendlyName
            is_enforced = [bool]$p.IsEnforced
            is_on_disk = [bool]$p.IsOnDisk
            is_authorized = $(if ($p.PSObject.Properties['IsAuthorized']) { [bool]$p.IsAuthorized } else { $null })
            policy_options = @($p.PolicyOptions)
        }
    }
}

function Assert-PolicyState([object[]]$Policies) {
    $baseId = Normalize-GuidText $BasePolicyId
    $candidateId = Normalize-GuidText $CandidateSupplementalPolicyId
    $base = @($Policies | Where-Object { $_.policy_id -eq $baseId })
    $candidate = @($Policies | Where-Object { $_.policy_id -eq $candidateId })
    if ($base.Count -ne 1) { throw "Base policy count is $($base.Count), expected 1." }
    if (-not $base[0].is_on_disk -or -not $base[0].is_enforced -or $base[0].is_authorized -eq $false) {
        throw 'Base policy is not active/enforced/authorized.'
    }
    if (@($base[0].policy_options) -contains 'Enabled:Audit Mode') { throw 'Base policy is in Audit mode.' }
    if (@($base[0].policy_options) -notcontains 'Enabled:Allow Supplemental Policies') {
        throw 'Base policy does not allow supplemental policies.'
    }
    if ($candidate.Count -ne 1) { throw "Candidate supplemental count is $($candidate.Count), expected 1." }
    if (-not $candidate[0].is_on_disk -or -not $candidate[0].is_enforced -or $candidate[0].is_authorized -eq $false) {
        throw 'Candidate supplemental is not active/enforced/authorized.'
    }
}

function Get-InstallInfo {
    $root = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ArvectumProxyLauncher'
    return [pscustomobject]@{
        root = $root
        exe = Join-Path $root 'Arvectum Proxy Launcher.exe'
        repair = Join-Path $root 'Arvectum Proxy Launcher Repair.exe'
        uninstaller = Join-Path $root 'unins000.exe'
        manifest = Join-Path $root 'build_manifest.json'
    }
}

function Invoke-Inno([string]$Path, [string]$LogPath, [string]$Label) {
    $p = Start-Process -FilePath $Path -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',("/LOG=$LogPath")) -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "$Label failed with exit code $($p.ExitCode)." }
}

function Invoke-Uninstall([string]$Path, [string]$LogPath) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Uninstaller is missing.' }
    $p = Start-Process -FilePath $Path -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/LOG=$LogPath")) -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Uninstall failed with exit code $($p.ExitCode)." }
}

function Wait-ForPacRuntime([object]$Installed, [int]$TimeoutSeconds = 25) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        foreach ($listener in @(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue)) {
            $owner = @(Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$listener.OwningProcess)" -ErrorAction SilentlyContinue)
            if ($owner.Count -eq 1 -and $owner[0].ExecutablePath) {
                if ([IO.Path]::GetFullPath([string]$owner[0].ExecutablePath) -ieq [IO.Path]::GetFullPath($Installed.exe)) {
                    try {
                        $pac = Invoke-WebRequest -UseBasicParsing -Uri $PacUrl -TimeoutSec 3
                        $inet = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
                        $auto = $inet.PSObject.Properties['AutoConfigURL']
                        if ($pac.StatusCode -eq 200 -and ([string]$pac.Content).Length -gt 100 -and $auto -and [string]$auto.Value -eq $PacUrl) {
                            return [ordered]@{
                                listener_pid = [int]$listener.OwningProcess
                                pac_http_status = [int]$pac.StatusCode
                                pac_body_length = ([string]$pac.Content).Length
                                auto_config_url = [string]$auto.Value
                            }
                        }
                    } catch {}
                }
            }
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw '0.2.4 runtime did not establish exact listener/PAC/AutoConfigURL before timeout.'
}

function Wait-ForPacStopped([int]$TimeoutSeconds = 20) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $listeners = @(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue)
        $inet = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        $auto = $inet.PSObject.Properties['AutoConfigURL']
        if ($listeners.Count -eq 0 -and (-not $auto -or [string]$auto.Value -ne $PacUrl)) { return }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Rollback did not remove governed listener/AutoConfigURL before timeout.'
}

function Assert-Installed([object]$Installed, [string]$ExpectedAppHash, [string]$ExpectedSetupHash, [string]$ExpectedVersion) {
    foreach ($path in @($Installed.exe,$Installed.repair,$Installed.uninstaller,$Installed.manifest)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Installed component missing: $path" }
    }
    if ((Get-Sha256 $Installed.exe) -ne $ExpectedAppHash) { throw 'Installed application SHA256 mismatch.' }
    if ((Get-Sha256 $Installed.repair) -ne $ExpectedSetupHash) { throw 'Cached Repair Setup SHA256 mismatch.' }
    $manifest = Get-Content -LiteralPath $Installed.manifest -Raw | ConvertFrom-Json
    if ([string]$manifest.version -ne $ExpectedVersion) { throw "Installed manifest version mismatch: $($manifest.version)" }
    if ([string]$manifest.application_sha256 -ne $ExpectedAppHash) { throw 'Installed manifest application SHA256 mismatch.' }
    if (-not (Test-Path -LiteralPath $UserUninstallKey)) { throw 'Uninstall registration is missing.' }
    $reg = Get-ItemProperty -LiteralPath $UserUninstallKey
    if ([string]$reg.DisplayVersion -ne $ExpectedVersion) { throw "Registered version mismatch: $($reg.DisplayVersion)" }
    return $manifest
}

function Get-Arvectum3077([DateTime]$Since) {
    $events = @(Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-CodeIntegrity/Operational'; Id=3077; StartTime=$Since } -ErrorAction SilentlyContinue)
    return @($events | Where-Object { ([string]$_.Message) -match '(?i)Arvectum|Proxy Launcher|ArvectumProxyLauncher' })
}

if (-not $IsolatedAcceptanceEnvironment) { throw 'SAFETY BLOCK: dedicated isolated acceptance host is required.' }
if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }

$candidateRoot = (Resolve-Path -LiteralPath $CandidateDirectory).Path
$candidateEvidencePath = Join-Path $candidateRoot 'candidate_evidence.json'
if (-not (Test-Path -LiteralPath $candidateEvidencePath -PathType Leaf)) { throw 'candidate_evidence.json is missing.' }
$candidate = Get-Content -LiteralPath $candidateEvidencePath -Raw | ConvertFrom-Json
if ([string]$candidate.product_version -ne '0.2.4') { throw 'Candidate is not 0.2.4.' }
if ([string]$candidate.supported_predecessor_version -ne '0.2.3') { throw 'Candidate predecessor contract is not 0.2.3.' }

$setup = Join-Path $candidateRoot ([string]$candidate.setup.filename)
$appPayload = Join-Path $candidateRoot ([string]$candidate.application.filename)
foreach ($path in @($setup,$appPayload)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Candidate file missing: $path" } }
$expectedSetupHash = ([string]$candidate.setup.sha256).ToLowerInvariant()
$expectedAppHash = ([string]$candidate.application.sha256).ToLowerInvariant()
if ((Get-Sha256 $setup) -ne $expectedSetupHash) { throw 'Candidate Setup drifted from evidence.' }
if ((Get-Sha256 $appPayload) -ne $expectedAppHash) { throw 'Candidate application drifted from evidence.' }

$previousSetup = Join-Path $PreviousReleaseDirectory 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe'
if (-not (Test-Path -LiteralPath $previousSetup -PathType Leaf)) { throw 'Canonical sealed 0.2.3 Setup is missing.' }
if ((Get-Sha256 $previousSetup) -ne $ExpectedPreviousSetupSha256) { throw 'Canonical sealed 0.2.3 Setup SHA256 mismatch.' }

New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$resultPath = Join-Path $EvidenceDirectory 'apl-win-014-final-0.2.4-physical-result.json'
if (Test-Path -LiteralPath $resultPath) { throw "Refusing to overwrite prior result: $resultPath" }

$final = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-final-0.2.4-physical.v1'
    task = 'APL-WIN-014'
    host = $env:COMPUTERNAME
    started_utc = [DateTime]::UtcNow.ToString('o')
    result = 'BLOCK'
    candidate_source_commit = [string]$candidate.candidate_source_commit
    candidate_setup_sha256 = $expectedSetupHash
    candidate_application_sha256 = $expectedAppHash
    predecessor_setup_sha256 = $ExpectedPreviousSetupSha256
    app_control = [ordered]@{ before = 'NOT_RUN'; after = 'NOT_RUN'; code_integrity_3077 = 'NOT_RUN' }
    gates = [ordered]@{ predecessor = 'NOT_RUN'; upgrade = 'NOT_RUN'; runtime = 'NOT_RUN'; rollback = 'NOT_RUN'; repair = 'NOT_RUN'; uninstall = 'NOT_RUN' }
    runtime = $null
    code_integrity_3077_count = $null
    block_reason = $null
}

$ciTool = Get-CiToolPath
$installed = Get-InstallInfo
$eventStart = Get-Date

try {
    Assert-PolicyState @(Get-AppControlPolicies $ciTool)
    $final.app_control.before = 'PASS'

    if (Test-Path -LiteralPath $installed.root) {
        if (-not (Test-Path -LiteralPath $installed.exe -PathType Leaf)) { throw 'Existing install root is incomplete; clean it deliberately before acceptance.' }
        if ((Get-Sha256 $installed.exe) -ne $ExpectedPreviousApplicationSha256) {
            throw 'Existing installation is not exact sealed 0.2.3 predecessor.'
        }
        $reg = if (Test-Path -LiteralPath $UserUninstallKey) { Get-ItemProperty -LiteralPath $UserUninstallKey } else { $null }
        if (-not $reg -or [string]$reg.DisplayVersion -ne '0.2.3') { throw 'Existing predecessor registration is not exact version 0.2.3.' }
    } else {
        Invoke-Inno $previousSetup (Join-Path $EvidenceDirectory '01-predecessor-install.log') 'Canonical predecessor install'
    }
    Assert-Installed $installed $ExpectedPreviousApplicationSha256 $ExpectedPreviousSetupSha256 '0.2.3' | Out-Null
    $final.gates.predecessor = 'PASS'

    Invoke-Inno $setup (Join-Path $EvidenceDirectory '02-upgrade-to-0.2.4.log') '0.2.3 -> 0.2.4 upgrade'
    Assert-Installed $installed $expectedAppHash $expectedSetupHash '0.2.4' | Out-Null
    $final.gates.upgrade = 'PASS'

    $starter = Start-Process -FilePath $installed.exe -ArgumentList @('--start') -PassThru
    $runtime = Wait-ForPacRuntime $installed
    $runtime.starter_pid = [int]$starter.Id
    $final.runtime = $runtime
    $final.gates.runtime = 'PASS'

    $rollback = Start-Process -FilePath $installed.exe -ArgumentList @('--rollback') -PassThru
    if (-not $rollback.WaitForExit(20000)) { throw '0.2.4 rollback did not return before timeout.' }
    if ($rollback.ExitCode -ne 0) { throw "0.2.4 rollback failed with exit code $($rollback.ExitCode)." }
    Wait-ForPacStopped
    $final.gates.rollback = 'PASS'

    Invoke-Inno $setup (Join-Path $EvidenceDirectory '03-repair-0.2.4.log') '0.2.4 repair'
    Assert-Installed $installed $expectedAppHash $expectedSetupHash '0.2.4' | Out-Null
    $final.gates.repair = 'PASS'

    Invoke-Uninstall $installed.uninstaller (Join-Path $EvidenceDirectory '04-uninstall-0.2.4.log')
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $installed.exe -PathType Leaf) { throw 'Application EXE remains after uninstall.' }
    if (Test-Path -LiteralPath $UserUninstallKey) { throw 'Uninstall registration remains after uninstall.' }
    $final.gates.uninstall = 'PASS'

    Assert-PolicyState @(Get-AppControlPolicies $ciTool)
    $final.app_control.after = 'PASS'

    $blocks = @(Get-Arvectum3077 $eventStart)
    $final.code_integrity_3077_count = $blocks.Count
    if ($blocks.Count -ne 0) {
        $blocks | Select-Object TimeCreated,Id,Message | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'code-integrity-3077.json') -Encoding utf8
        throw "Detected $($blocks.Count) Arvectum-related Code Integrity 3077 block(s)."
    }
    $final.app_control.code_integrity_3077 = 'PASS'

    $final.result = 'PASS'
}
catch {
    $final.block_reason = $_.Exception.Message
    throw
}
finally {
    $final.finished_utc = [DateTime]::UtcNow.ToString('o')
    $final | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding utf8
    Write-Host "Physical result: $resultPath"
    Write-Host "APL-WIN-014 final 0.2.4 result: $($final.result)"
}
