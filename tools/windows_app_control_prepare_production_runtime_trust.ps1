<#
.SYNOPSIS
    Prepare the production APL-WIN-014 Inno runtime evidence and ReferenceFullHash trust pack.
.DESCRIPTION
    Authoring-only wrapper. It verifies exact production bytes against canonical upstream
    signing evidence, statically extracts the Inno Setup 6.7.1 child runtime, proves the
    runtime anchor, and invokes the enterprise trust-pack generator. Exact installer
    maintenance helpers are supplied separately from governed release-source material.
    CryptoPro/Rutoken is not required on this acceptance/customer host.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [Guid]$BasePolicyId,
    [Parameter(Mandatory = $true)] [string]$SigningEvidencePath,
    [Parameter(Mandatory = $true)] [string]$MaintenanceSourceRoot,
    [string]$ReleaseDirectory = 'C:\Arvectum\Releases\0.2.3-russian-production',
    [string]$InstalledRoot = '',
    [string]$RuntimeDirectory = 'C:\Arvectum\Evidence\APL-WIN-014\runtime',
    [string]$TrustPackDirectory = 'C:\Arvectum\Evidence\APL-WIN-014\trust-pack',
    [string]$PythonCommand = 'python.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Production runtime trust authoring must run on Windows.' }

$ExpectedSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
$ExpectedSigningEvidenceSha256 = '67d379db11a238960b9324c8054e73790cf18b1eaa85db8c04a9226bb27bc58e'
$ExpectedUpgradeHelperSha256 = '77e8bcb4d27aad5b2d1b40753f3ec2dfa2419e48a07f2eb17a7b15f2a9232218'
$ExpectedUninstallHelperSha256 = '7abc1fe332975440d2c84be608773a890c5bb4deb130eea54378a128e79b0a44'
$ExpectedRuntimeSize = 4473344
$ExpectedRuntimeSha256 = 'b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8'
$ExpectedRuntimeCrc32 = '021edadf'
$ExpectedPefileVersion = '2024.8.26'

$extractor = Join-Path $PSScriptRoot 'bootstrap\apl-win-014\extract_inno_6_7_1_runtime.py'
$validator = Join-Path $PSScriptRoot 'windows_app_control_inno_runtime_material.ps1'
$packGenerator = Join-Path $PSScriptRoot 'windows_app_control_enterprise_trust_pack.ps1'
foreach ($required in @($extractor,$validator,$packGenerator,$SigningEvidencePath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required authoring input/tool is missing: $required" }
}
if ((Get-FileHash -LiteralPath $SigningEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedSigningEvidenceSha256) {
    throw 'Canonical Russian signing evidence SHA256 mismatch.'
}

$MaintenanceSourceRoot = (Resolve-Path -LiteralPath $MaintenanceSourceRoot).Path
$maintenanceUpgrade = Join-Path $MaintenanceSourceRoot 'upgrade_helper.ps1'
$maintenanceUninstall = Join-Path $MaintenanceSourceRoot 'uninstall_helper.ps1'
foreach ($required in @($maintenanceUpgrade,$maintenanceUninstall)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required sealed maintenance helper is missing: $required" }
}
if ((Get-FileHash -LiteralPath $maintenanceUpgrade -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedUpgradeHelperSha256) {
    throw 'Sealed upgrade_helper.ps1 SHA256 mismatch.'
}
if ((Get-FileHash -LiteralPath $maintenanceUninstall -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedUninstallHelperSha256) {
    throw 'Sealed uninstall_helper.ps1 SHA256 mismatch.'
}

$python = Get-Command $PythonCommand -ErrorAction SilentlyContinue
if (-not $python) { throw "Python command is unavailable: $PythonCommand" }
$pefileVersion = (& $python.Source -c "import pefile; print(pefile.__version__)" 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to import pefile with $PythonCommand. Install tools/bootstrap/apl-win-014/requirements-runtime-evidence.txt first." }
if ($pefileVersion -ne $ExpectedPefileVersion) { throw "pefile version mismatch: expected $ExpectedPefileVersion, got $pefileVersion" }

$ReleaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$SigningEvidencePath = (Resolve-Path -LiteralPath $SigningEvidencePath).Path
$setup = Join-Path $ReleaseDirectory 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe'
if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw "Canonical production Setup is missing: $setup" }
$setupHash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
if ($setupHash -ne $ExpectedSetupSha256) { throw "Production Setup SHA256 mismatch: $setupHash" }

if (-not $InstalledRoot) { $InstalledRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ArvectumProxyLauncher' }
$InstalledRoot = (Resolve-Path -LiteralPath $InstalledRoot).Path
if (Test-Path -LiteralPath $RuntimeDirectory) { throw "Runtime evidence directory already exists; refusing to overwrite prior evidence: $RuntimeDirectory" }
if (Test-Path -LiteralPath $TrustPackDirectory) { throw "Trust-pack directory already exists; refusing to overwrite prior evidence: $TrustPackDirectory" }
New-Item -ItemType Directory -Path $RuntimeDirectory -Force | Out-Null

$runtimePath = Join-Path $RuntimeDirectory 'inno-setup-6.7.1-runtime-stub.exe'
$runtimeEvidencePath = Join-Path $RuntimeDirectory 'production-runtime-extraction.json'
Write-Host '=== Static extraction from exact production Setup ==='
& $python.Source $extractor $setup $runtimePath --evidence $runtimeEvidencePath
if ($LASTEXITCODE -ne 0) { throw "Inno runtime extraction failed with exit code $LASTEXITCODE" }

try { $runtimeOutput = @(& $validator -RuntimePath $runtimePath -RuntimeEvidencePath $runtimeEvidencePath -ExpectedSetupSha256 $ExpectedSetupSha256 -AsJson) }
catch { throw "Inno runtime validation command failed: $($_.Exception.Message)" }
$runtimeJson = ($runtimeOutput | Out-String).Trim()
if (-not $runtimeJson) { throw 'Inno runtime validation command returned no JSON evidence.' }
try { $runtime = $runtimeJson | ConvertFrom-Json }
catch { throw "Inno runtime validation command returned invalid JSON: $($_.Exception.Message)" }
if ([long]$runtime.size -ne $ExpectedRuntimeSize -or $runtime.sha256 -ne $ExpectedRuntimeSha256 -or $runtime.crc32 -ne $ExpectedRuntimeCrc32) {
    throw 'Production runtime did not match the independently accepted Inno 6.7.1 runtime anchor.'
}

$authoringEvidence = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-production-runtime-authoring.v1'; task = 'APL-WIN-014'; created_utc = [DateTime]::UtcNow.ToString('o')
    production_setup_sha256 = $setupHash; signing_evidence_sha256 = $ExpectedSigningEvidenceSha256; local_cryptopro_verification = 'NOT_REQUIRED'
    maintenance_source_root = $MaintenanceSourceRoot; upgrade_helper_sha256 = $ExpectedUpgradeHelperSha256; uninstall_helper_sha256 = $ExpectedUninstallHelperSha256
    runtime_size = [long]$runtime.size; runtime_sha256 = $runtime.sha256; runtime_crc32 = $runtime.crc32
    official_inno_tag = $runtime.official_inno_tag; official_inno_commit = $runtime.official_inno_commit
    evidence_workflow_run = $runtime.evidence_workflow_run; behavioral_workflow_run = $runtime.behavioral_workflow_run
    static_to_behavioral_anchor = $runtime.static_to_behavioral_anchor; product_rebuilt = $false; policy_deployed = $false
    security_controls_modified = $false; result = 'PASS'
}
$authoringEvidencePath = Join-Path $RuntimeDirectory 'production-runtime-authoring.json'
$authoringEvidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $authoringEvidencePath -Encoding UTF8

Write-Host '=== Generate canonical ReferenceFullHash trust pack ==='
& $packGenerator -ReleaseDirectory $ReleaseDirectory -BasePolicyId $BasePolicyId -SigningEvidencePath $SigningEvidencePath -MaintenanceSourceRoot $MaintenanceSourceRoot -Mode ReferenceFullHash -InstalledRoot $InstalledRoot -InnoRuntimePath $runtimePath -InnoRuntimeEvidencePath $runtimeEvidencePath -OutputDirectory $TrustPackDirectory

$verifier = Join-Path $PSScriptRoot 'windows_app_control_verify_runtime_trust_pack.ps1'
& $verifier -TrustPackDirectory $TrustPackDirectory

$checksumsPath = Join-Path $RuntimeDirectory 'SHA256SUMS.txt'
$checksums = @(Get-ChildItem -LiteralPath $RuntimeDirectory -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | Sort-Object Name | ForEach-Object { "$(($h = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)" })
Set-Content -LiteralPath $checksumsPath -Value $checksums -Encoding ASCII

Write-Host ''
Write-Host 'APL-WIN-014 production runtime trust authoring: PASS'
Write-Host "Production Setup SHA256: $ExpectedSetupSha256"
Write-Host "Signing evidence SHA256: $ExpectedSigningEvidenceSha256"
Write-Host "Maintenance source root: $MaintenanceSourceRoot"
Write-Host "Upgrade helper SHA256: $ExpectedUpgradeHelperSha256"
Write-Host "Uninstall helper SHA256: $ExpectedUninstallHelperSha256"
Write-Host 'Local CryptoPro verification: NOT_REQUIRED'
Write-Host "Inno runtime SHA256: $ExpectedRuntimeSha256"
Write-Host "Runtime evidence: $RuntimeDirectory"
Write-Host "ReferenceFullHash trust pack: $TrustPackDirectory"
Write-Host 'Product rebuilt: NO'
Write-Host 'Policy deployed: NO'
Write-Host 'Security controls modified: NO'