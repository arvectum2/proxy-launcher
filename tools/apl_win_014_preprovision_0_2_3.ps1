<#
.SYNOPSIS
    Provision the exact sealed 0.2.3 predecessor state for final APL-WIN-014 acceptance.
.DESCRIPTION
    The sealed 0.2.3 Setup predates the PowerShell/WDAC hardening used by 0.2.4.
    Under enforced App Control its legacy embedded maintenance helper cannot be used as
    the acceptance bootstrap. This helper preserves the exact 0.2.3 Setup-created Inno
    state, then restores only the missing application payload from the exact canonical
    0.2.3 portable ZIP and verifies the complete predecessor identity fail-closed.

    Run only after the final supplemental App Control policy has been deployed. The
    helper never changes, removes, or weakens App Control policy.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$PreviousReleaseDirectory = 'C:\Arvectum\Releases\0.2.3-russian-production',
    [string]$EvidenceDirectory = 'C:\Arvectum\Evidence\APL-WIN-014\predecessor-0.2.3-final'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
$ExpectedPortableSha256 = '62d313547b4d8c2c8e6951d6cd866bb954fdf199ad7650063c8ed3bfbc455801'
$ExpectedApplicationSha256 = 'f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a'
$AppKeyName = '{6A5A0706-4015-4EAF-BFA1-25EF435C9E1B}_is1'
$UserUninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppKeyName"

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-ExactFile([string]$Path, [string]$ExpectedSha256, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    $actual = Get-Sha256 $Path
    if ($actual -ne $ExpectedSha256) { throw "$Label SHA256 mismatch: expected $ExpectedSha256, got $actual" }
}

function Get-InstallInfo {
    $root = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ArvectumProxyLauncher'
    return [pscustomobject]@{
        root = $root
        exe = Join-Path $root 'Arvectum Proxy Launcher.exe'
        repair = Join-Path $root 'Arvectum Proxy Launcher Repair.exe'
        uninstaller = Join-Path $root 'unins000.exe'
        uninstallerData = Join-Path $root 'unins000.dat'
        manifest = Join-Path $root 'build_manifest.json'
    }
}

function Assert-PredecessorState([object]$Installed) {
    foreach ($path in @($Installed.exe,$Installed.repair,$Installed.uninstaller,$Installed.uninstallerData,$Installed.manifest)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Predecessor component missing: $path" }
    }
    Assert-ExactFile $Installed.exe $ExpectedApplicationSha256 'installed 0.2.3 application'
    Assert-ExactFile $Installed.repair $ExpectedSetupSha256 'cached 0.2.3 Repair Setup'

    $manifest = Get-Content -LiteralPath $Installed.manifest -Raw | ConvertFrom-Json
    if ([string]$manifest.version -ne '0.2.3') { throw "Predecessor manifest version mismatch: $($manifest.version)" }
    if (([string]$manifest.application_sha256).ToLowerInvariant() -ne $ExpectedApplicationSha256) {
        throw 'Predecessor manifest application SHA256 mismatch.'
    }

    if (-not (Test-Path -LiteralPath $UserUninstallKey)) { throw 'Predecessor uninstall registration is missing.' }
    $reg = Get-ItemProperty -LiteralPath $UserUninstallKey
    if ([string]$reg.DisplayVersion -ne '0.2.3') { throw "Predecessor registered version mismatch: $($reg.DisplayVersion)" }
    if ([string]$reg.InstallLocation -and ([string]$reg.InstallLocation).TrimEnd('\') -ine $Installed.root.TrimEnd('\')) {
        throw "Predecessor InstallLocation mismatch: $($reg.InstallLocation)"
    }
    return $manifest
}

if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
$PreviousReleaseDirectory = (Resolve-Path -LiteralPath $PreviousReleaseDirectory).Path
if (Test-Path -LiteralPath $EvidenceDirectory) { throw "Refusing to overwrite predecessor evidence: $EvidenceDirectory" }
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null

$setup = Join-Path $PreviousReleaseDirectory 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe'
$portable = Join-Path $PreviousReleaseDirectory 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-portable.zip'
Assert-ExactFile $setup $ExpectedSetupSha256 'canonical 0.2.3 Setup'
Assert-ExactFile $portable $ExpectedPortableSha256 'canonical 0.2.3 portable ZIP'

$installed = Get-InstallInfo
if (Test-Path -LiteralPath $installed.root) {
    throw "Predecessor install root must be absent before preprovisioning: $($installed.root)"
}
if (Test-Path -LiteralPath $UserUninstallKey) {
    throw 'Predecessor uninstall registration must be absent before preprovisioning.'
}

$setupLog = Join-Path $EvidenceDirectory '01-canonical-0.2.3-setup.log'
$p = Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',("/LOG=$setupLog")) -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Canonical 0.2.3 Setup failed with exit code $($p.ExitCode)." }

# The legacy Setup is expected to create the canonical Inno registration/supporting
# files. Its embedded pre-hardening helper can leave the application EXE absent under
# enforced App Control. No other missing predecessor component is repaired here.
foreach ($path in @($installed.repair,$installed.uninstaller,$installed.uninstallerData,$installed.manifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Canonical 0.2.3 Setup did not create required predecessor state: $path"
    }
}
Assert-ExactFile $installed.repair $ExpectedSetupSha256 'cached 0.2.3 Repair Setup'
if (-not (Test-Path -LiteralPath $UserUninstallKey)) { throw 'Canonical 0.2.3 Setup did not create uninstall registration.' }
$regBefore = Get-ItemProperty -LiteralPath $UserUninstallKey
if ([string]$regBefore.DisplayVersion -ne '0.2.3') { throw "Canonical Setup registered unexpected version: $($regBefore.DisplayVersion)" }

$appWasMissing = -not (Test-Path -LiteralPath $installed.exe -PathType Leaf)
if (-not $appWasMissing) {
    Assert-ExactFile $installed.exe $ExpectedApplicationSha256 'application produced by canonical 0.2.3 Setup'
}

$tempRoot = Join-Path $env:TEMP ("ArvectumAplWin014Pred023-$([Guid]::NewGuid().ToString('N'))")
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    Expand-Archive -LiteralPath $portable -DestinationPath $tempRoot -Force
    $matches = @()
    foreach ($item in @(Get-ChildItem -LiteralPath $tempRoot -Recurse -File -Filter 'Arvectum Proxy Launcher.exe')) {
        if ((Get-Sha256 $item.FullName) -eq $ExpectedApplicationSha256) { $matches += $item }
    }
    if ($matches.Count -ne 1) { throw "Canonical portable must contain exactly one exact 0.2.3 application; found $($matches.Count)." }

    if ($appWasMissing) {
        Copy-Item -LiteralPath $matches[0].FullName -Destination $installed.exe -Force
    }
    Assert-ExactFile $installed.exe $ExpectedApplicationSha256 'preprovisioned 0.2.3 application'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

$manifest = Assert-PredecessorState $installed
$result = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-predecessor-0.2.3-preprovision.v1'
    task = 'APL-WIN-014'
    host = $env:COMPUTERNAME
    result = 'PASS'
    predecessor_version = '0.2.3'
    setup_sha256 = $ExpectedSetupSha256
    portable_sha256 = $ExpectedPortableSha256
    application_sha256 = $ExpectedApplicationSha256
    install_root = $installed.root
    legacy_setup_application_missing = $appWasMissing
    application_source = $(if ($appWasMissing) { 'CANONICAL_PORTABLE_EXACT_BYTES' } else { 'CANONICAL_SETUP_EXACT_BYTES' })
    registered_version = '0.2.3'
    manifest_version = [string]$manifest.version
    app_control_modified = $false
    security_controls_weakened = $false
    created_utc = [DateTime]::UtcNow.ToString('o')
}
$resultPath = Join-Path $EvidenceDirectory 'apl-win-014-predecessor-0.2.3-preprovision.json'
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8

Write-Host ''
Write-Host 'APL-WIN-014 exact 0.2.3 predecessor preprovision: PASS'
Write-Host "Install root: $($installed.root)"
Write-Host "Application SHA256: $ExpectedApplicationSha256"
Write-Host "Evidence: $resultPath"
Write-Host 'App Control modified: NO'
Write-Host 'Security controls weakened: NO'
