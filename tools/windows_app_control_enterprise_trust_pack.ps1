<#
.SYNOPSIS
    Generate a Russian-first App Control for Business trust pack for APL-WIN-014.
.DESCRIPTION
    Validates the exact v0.2.3-ru.2 release bytes against canonical owner-station
    signing evidence, then generates a customer-IT supplemental App Control policy
    using exact hash rules. CryptoPro/Rutoken is NOT required on the customer or
    acceptance host; detached-signature verification is an upstream release-control
    and the immutable evidence record is revalidated here by exact hash and fields.

    The sealed production portable ZIP is used only for the portable application EXE.
    The production installer embeds upgrade/uninstall maintenance scripts from the
    governed release source tree, so those exact helper bytes are supplied separately
    through MaintenanceSourceRoot and must match their fixed release SHA256 identities.

    BootstrapHash mode covers the exact production Setup, application EXE, the exact
    upgrade/uninstall maintenance scripts, and the exact Inno Setup 6.7.1 child runtime.
    ReferenceFullHash additionally scans an exact installed reference tree.

    Script enforcement remains enabled. Exact maintenance scripts are included by hash.
    The script never deploys a policy and never weakens Windows protection.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$ReleaseDirectory,
    [Parameter(Mandatory = $true)] [Guid]$BasePolicyId,
    [Parameter(Mandatory = $true)] [string]$SigningEvidencePath,
    [Parameter(Mandatory = $true)] [string]$MaintenanceSourceRoot,
    [ValidateSet('BootstrapHash','ReferenceFullHash')] [string]$Mode = 'BootstrapHash',
    [string]$InstalledRoot = '',
    [string]$InnoRuntimePath = 'C:\Arvectum\Evidence\APL-WIN-014\runtime\inno-setup-6.7.1-runtime-stub.exe',
    [string]$InnoRuntimeEvidencePath = 'C:\Arvectum\Evidence\APL-WIN-014\runtime\production-runtime-extraction.json',
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'APL-WIN-014 enterprise trust-pack generation must run on Windows.' }

$ExpectedVersion = '0.2.3'
$ExpectedReleaseTag = 'v0.2.3-ru.2'
$ExpectedReleaseCommit = '47823585c42da54ab51dc2246583dc24d74d4ba6'
$ExpectedSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
$ExpectedPortableSha256 = '62d313547b4d8c2c8e6951d6cd866bb954fdf199ad7650063c8ed3bfbc455801'
$ExpectedAppSha256 = 'f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a'
$ExpectedUpgradeHelperSha256 = '77e8bcb4d27aad5b2d1b40753f3ec2dfa2419e48a07f2eb17a7b15f2a9232218'
$ExpectedUninstallHelperSha256 = '7abc1fe332975440d2c84be608773a890c5bb4deb130eea54378a128e79b0a44'
$ExpectedSignerThumbprint = 'EE1CFA955BA22F03C39C76B183D94CD37494582E'
$ExpectedSigningEvidenceSha256 = '67d379db11a238960b9324c8054e73790cf18b1eaa85db8c04a9226bb27bc58e'
$ExpectedTrustSchema = 'arvectum.proxy.windows-app-control-enterprise-trust-pack.v1'
$MaintenanceScriptNames = @('upgrade_helper.ps1','uninstall_helper.ps1')

function Get-Sha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Assert-Command([string]$Name) { if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Required Windows command/cmdlet is unavailable: $Name" } }
function Get-PolicyIdFromXml([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $match = [regex]::Match($text, '<PolicyID>\s*([^<]+)\s*</PolicyID>', 'IgnoreCase')
    if (-not $match.Success) { throw 'Generated App Control policy has no PolicyID.' }
    return $match.Groups[1].Value.Trim()
}
function Get-OnePortableFile([string]$Root, [string]$Name) {
    $matches = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $Name)
    if ($matches.Count -ne 1) { throw "Portable archive must contain exactly one $Name; found $($matches.Count)." }
    return $matches[0].FullName
}
function Invoke-JsonHelper([string]$ScriptPath, [hashtable]$Arguments, [string]$Label) {
    try { $output = @(& $ScriptPath @Arguments) }
    catch { throw "$Label failed: $($_.Exception.Message)" }
    $json = ($output | Out-String).Trim()
    if (-not $json) { throw "$Label returned no JSON evidence." }
    try { return ($json | ConvertFrom-Json) }
    catch { throw "$Label returned invalid JSON: $($_.Exception.Message)" }
}

$runtimeHelper = Join-Path $PSScriptRoot 'windows_app_control_inno_runtime_material.ps1'
$preverifiedHelper = Join-Path $PSScriptRoot 'windows_app_control_preverified_release.ps1'
foreach ($requiredTool in @($runtimeHelper,$preverifiedHelper)) {
    if (-not (Test-Path -LiteralPath $requiredTool -PathType Leaf)) { throw "Required trust helper is missing: $requiredTool" }
}

$ReleaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$SigningEvidencePath = (Resolve-Path -LiteralPath $SigningEvidencePath).Path
$MaintenanceSourceRoot = (Resolve-Path -LiteralPath $MaintenanceSourceRoot).Path
$setup = Join-Path $ReleaseDirectory 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe'
$portable = Join-Path $ReleaseDirectory 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-portable.zip'
$upgradeHelper = Join-Path $MaintenanceSourceRoot 'upgrade_helper.ps1'
$uninstallHelper = Join-Path $MaintenanceSourceRoot 'uninstall_helper.ps1'
foreach ($required in @($setup,$portable,$SigningEvidencePath,$upgradeHelper,$uninstallHelper)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required production release input is missing: $required" }
}

$setupHash = Get-Sha256 $setup
$portableHash = Get-Sha256 $portable
$upgradeHelperHash = Get-Sha256 $upgradeHelper
$uninstallHelperHash = Get-Sha256 $uninstallHelper
if ($setupHash -ne $ExpectedSetupSha256) { throw 'Production installer SHA256 mismatch.' }
if ($portableHash -ne $ExpectedPortableSha256) { throw 'Production portable ZIP SHA256 mismatch.' }
if ((Get-Sha256 $SigningEvidencePath) -ne $ExpectedSigningEvidenceSha256) { throw 'Canonical Russian signing evidence file SHA256 mismatch.' }
if ($upgradeHelperHash -ne $ExpectedUpgradeHelperSha256) { throw 'MaintenanceSourceRoot upgrade_helper.ps1 does not match the sealed v0.2.3-ru.2 helper identity.' }
if ($uninstallHelperHash -ne $ExpectedUninstallHelperSha256) { throw 'MaintenanceSourceRoot uninstall_helper.ps1 does not match the sealed v0.2.3-ru.2 helper identity.' }

Write-Host '=== APL-WIN-014 upstream Russian release provenance ==='
$preverified = Invoke-JsonHelper -ScriptPath $preverifiedHelper -Label 'Preverified Russian release validation' -Arguments @{
    ReleaseDirectory = $ReleaseDirectory
    SigningEvidencePath = $SigningEvidencePath
    AsJson = $true
}
if ([string]$preverified.verification -ne 'PREVERIFIED_EXACT_HASH_BOUND') { throw 'Release provenance is not PREVERIFIED_EXACT_HASH_BOUND.' }
if ([string]$preverified.local_cryptopro_verification -ne 'NOT_REQUIRED') { throw 'Acceptance-host CryptoPro boundary mismatch.' }
if (([string]$preverified.signing_evidence_sha256).ToLowerInvariant() -ne $ExpectedSigningEvidenceSha256) { throw 'Preverified signing evidence identity mismatch.' }
if (([string]$preverified.signer_thumbprint).ToUpperInvariant() -ne $ExpectedSignerThumbprint) { throw 'Preverified signer thumbprint mismatch.' }
Write-Host 'Exact release bytes: PASS'
Write-Host 'Russian signature provenance: PREVERIFIED_EXACT_HASH_BOUND'
Write-Host 'Local CryptoPro verification: NOT_REQUIRED'
Write-Host 'Maintenance helper source: SEALED RELEASE SOURCE / EXACT SHA256'

$runtime = Invoke-JsonHelper -ScriptPath $runtimeHelper -Label 'Inno runtime validation' -Arguments @{
    RuntimePath = $InnoRuntimePath
    RuntimeEvidencePath = $InnoRuntimeEvidencePath
    ExpectedSetupSha256 = $ExpectedSetupSha256
    AsJson = $true
}

Assert-Command 'New-CIPolicy'
Assert-Command 'Set-CIPolicyIdInfo'
Assert-Command 'Set-CIPolicyVersion'
Assert-Command 'ConvertFrom-CIPolicy'

if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PWD ("out\app-control-trust-pack-$ExpectedVersion-$Mode") }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw "Output directory already exists; refusing to overwrite a prior trust pack: $OutputDirectory" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$tempRoot = Join-Path $env:TEMP ("ArvectumAppControlPack-" + [guid]::NewGuid().ToString('N'))
$portableExtract = Join-Path $tempRoot 'portable'
$scanRoot = Join-Path $tempRoot 'scan'
New-Item -ItemType Directory -Path $portableExtract -Force | Out-Null
New-Item -ItemType Directory -Path $scanRoot -Force | Out-Null

try {
    Expand-Archive -LiteralPath $portable -DestinationPath $portableExtract -Force
    $appExe = Get-OnePortableFile -Root $portableExtract -Name 'Arvectum Proxy Launcher.exe'
    $appHash = Get-Sha256 $appExe
    if ($appHash -ne $ExpectedAppSha256) { throw 'Portable application EXE SHA256 mismatch.' }

    Copy-Item -LiteralPath $setup -Destination (Join-Path $scanRoot 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe') -Force
    Copy-Item -LiteralPath $appExe -Destination (Join-Path $scanRoot 'Arvectum Proxy Launcher.exe') -Force
    Copy-Item -LiteralPath $upgradeHelper -Destination (Join-Path $scanRoot 'upgrade_helper.ps1') -Force
    Copy-Item -LiteralPath $uninstallHelper -Destination (Join-Path $scanRoot 'uninstall_helper.ps1') -Force
    $runtimeStage = Join-Path $scanRoot $runtime.filename
    Copy-Item -LiteralPath $runtime.path -Destination $runtimeStage -Force
    if ((Get-Sha256 $runtimeStage) -ne $runtime.sha256) { throw 'Staged Inno runtime bytes drifted before ConfigCI policy authoring.' }

    $referenceFiles = @()
    if ($Mode -eq 'ReferenceFullHash') {
        if (-not $InstalledRoot) { $InstalledRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ArvectumProxyLauncher' }
        $InstalledRoot = (Resolve-Path -LiteralPath $InstalledRoot).Path
        $installedExe = Join-Path $InstalledRoot 'Arvectum Proxy Launcher.exe'
        $repairSetup = Join-Path $InstalledRoot 'Arvectum Proxy Launcher Repair.exe'
        $installedUpgrade = Join-Path $InstalledRoot 'upgrade_helper.ps1'
        $installedUninstall = Join-Path $InstalledRoot 'uninstall_helper.ps1'
        if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) { throw "Reference installation launcher is missing: $installedExe" }
        if ((Get-Sha256 $installedExe) -ne $ExpectedAppSha256) { throw 'Reference installation does not contain the exact sealed application EXE.' }
        if (-not (Test-Path -LiteralPath $repairSetup -PathType Leaf)) { throw 'Reference installation cached repair Setup is missing.' }
        if ((Get-Sha256 $repairSetup) -ne $ExpectedSetupSha256) { throw 'Reference cached repair Setup does not match the exact production installer.' }
        if (-not (Test-Path -LiteralPath $installedUpgrade -PathType Leaf) -or (Get-Sha256 $installedUpgrade) -ne $ExpectedUpgradeHelperSha256) { throw 'Reference installation upgrade_helper.ps1 does not match the sealed release helper.' }
        if (-not (Test-Path -LiteralPath $installedUninstall -PathType Leaf) -or (Get-Sha256 $installedUninstall) -ne $ExpectedUninstallHelperSha256) { throw 'Reference installation uninstall_helper.ps1 does not match the sealed release helper.' }
        $referenceStage = Join-Path $scanRoot 'installed-reference-tree'
        Copy-Item -LiteralPath $InstalledRoot -Destination $referenceStage -Recurse -Force
        $referenceFiles = @(Get-ChildItem -LiteralPath $InstalledRoot -File -Recurse -Force | ForEach-Object {
            [ordered]@{ relative_path = $_.FullName.Substring($InstalledRoot.Length).TrimStart('\'); sha256 = Get-Sha256 $_.FullName; size = [long]$_.Length }
        })
    }

    $policyXml = Join-Path $OutputDirectory 'Arvectum-Proxy-Launcher-AppControl-Supplemental.xml'
    $policyName = "Arvectum Proxy Launcher $ExpectedVersion Exact Hash"
    Write-Host '=== Generating exact-hash App Control policy ==='
    New-CIPolicy -MultiplePolicyFormat -ScanPath $scanRoot -UserPEs -NoShadowCopy -FilePath $policyXml -Level Hash | Out-Null
    $policyXmlText = Get-Content -LiteralPath $policyXml -Raw -Encoding UTF8
    if ($policyXmlText -match 'Disabled:Script Enforcement') { throw 'Generated product supplemental policy disables script enforcement; refusing unsafe trust pack.' }
    foreach ($scriptName in $MaintenanceScriptNames) { if ($policyXmlText -notmatch [regex]::Escape($scriptName)) { throw "Generated product supplemental policy is missing exact script rules for $scriptName." } }

    Set-CIPolicyIdInfo -FilePath $policyXml -ResetPolicyID -PolicyName $policyName -SupplementsBasePolicyID $BasePolicyId | Out-Null
    Set-CIPolicyVersion -FilePath $policyXml -Version '0.2.3.0'
    $policyId = Get-PolicyIdFromXml $policyXml
    $policyCip = Join-Path $OutputDirectory ("{$($policyId.Trim('{}'))}.cip")
    ConvertFrom-CIPolicy -XmlFilePath $policyXml -BinaryFilePath $policyCip
    if (-not (Test-Path -LiteralPath $policyCip -PathType Leaf)) { throw 'ConfigCI did not create the binary supplemental policy.' }

    $authSetup = Get-AuthenticodeSignature -LiteralPath $setup
    $authApp = Get-AuthenticodeSignature -LiteralPath $appExe
    $manifest = [ordered]@{
        schema = $ExpectedTrustSchema
        task = 'APL-WIN-014'
        created_utc = [DateTime]::UtcNow.ToString('o')
        version = $ExpectedVersion
        release_tag = $ExpectedReleaseTag
        release_commit = $ExpectedReleaseCommit
        exact_release_identity = 'PASS'
        russian_release_provenance = 'PREVERIFIED_EXACT_HASH_BOUND'
        local_cryptopro_verification = 'NOT_REQUIRED'
        signing_evidence_sha256 = $ExpectedSigningEvidenceSha256
        russian_release_signer_thumbprint = $ExpectedSignerThumbprint
        mode = $Mode
        base_policy_id = $BasePolicyId.ToString('B')
        supplemental_policy_id = $policyId
        supplemental_policy_xml = [IO.Path]::GetFileName($policyXml)
        supplemental_policy_cip = [IO.Path]::GetFileName($policyCip)
        release = [ordered]@{
            installer_sha256 = $setupHash
            portable_zip_sha256 = $portableHash
            application_exe_sha256 = $appHash
            installer_authenticode_status = [string]$authSetup.Status
            application_authenticode_status = [string]$authApp.Status
        }
        maintenance_source = [ordered]@{
            root = $MaintenanceSourceRoot
            release_commit = $ExpectedReleaseCommit
            contract = 'SEALED_RELEASE_SOURCE_EXACT_HASH'
        }
        maintenance_scripts = @(
            [ordered]@{ filename='upgrade_helper.ps1'; sha256=$upgradeHelperHash },
            [ordered]@{ filename='uninstall_helper.ps1'; sha256=$uninstallHelperHash }
        )
        script_enforcement_preserved = $true
        inno_runtime = [ordered]@{
            filename = $runtime.filename
            size = $runtime.size
            sha256 = $runtime.sha256
            crc32 = $runtime.crc32
            source_setup_sha256 = $runtime.source_setup_sha256
            extraction_evidence_sha256 = $runtime.extraction_evidence_sha256
            observed_compressed_chunk_count = $runtime.observed_compressed_chunk_count
            official_inno_tag = $runtime.official_inno_tag
            official_inno_commit = $runtime.official_inno_commit
            evidence_workflow_run = $runtime.evidence_workflow_run
            behavioral_workflow_run = $runtime.behavioral_workflow_run
            historical_anchor_setup_sha256 = $runtime.historical_anchor_setup_sha256
            behavioral_anchor_workflow_run = $runtime.behavioral_workflow_run
            behavioral_anchor_setup_sha256 = $runtime.behavioral_anchor_setup_sha256
            static_to_behavioral_anchor = $runtime.static_to_behavioral_anchor
            hash_policy_integrated = $true
        }
        policy_scope = $(if ($Mode -eq 'BootstrapHash') { 'exact production Setup + exact production application EXE + exact release-source upgrade/uninstall maintenance scripts + exact Inno Setup 6.7.1 child runtime derived from that Setup' } else { 'exact production Setup + complete exact reference installation tree including generated maintenance binaries + exact release-source upgrade/uninstall maintenance scripts + exact Inno Setup 6.7.1 child runtime derived from that Setup' })
        reference_files = $referenceFiles
        deployment_invariants = @(
            'pack generation never deploys App Control policy',
            'customer base policy must allow supplemental policies',
            'Smart App Control must not be disabled as a workaround',
            'script enforcement remains enabled; only exact release maintenance scripts are allowed by hash',
            'maintenance helper bytes come from explicit governed release-source material and must match fixed release SHA256 identities',
            'hash policy is release-specific and must be regenerated for changed bytes',
            'Inno child runtime trust is bound to exact runtime bytes statically derived from the exact production Setup and independently behaviorally cross-validated',
            'Russian detached release provenance was verified upstream and is rebound locally through canonical signing evidence',
            'CryptoPro/Rutoken is not required on customer or acceptance endpoints'
        )
        result = 'PASS'
    }
    $manifestPath = Join-Path $OutputDirectory 'trust-pack.json'
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $deployment = @"
ARVECTUM PROXY LAUNCHER - APP CONTROL FOR BUSINESS TRUST PACK
=============================================================
Task: APL-WIN-014
Release: $ExpectedReleaseTag / version $ExpectedVersion
Mode: $Mode
Base policy ID: $($BasePolicyId.ToString('B'))
Supplemental policy ID: $policyId
Signing evidence SHA256: $ExpectedSigningEvidenceSha256
Russian signature provenance: PREVERIFIED_EXACT_HASH_BOUND
Local CryptoPro/Rutoken requirement: NONE
Maintenance source contract: SEALED_RELEASE_SOURCE_EXACT_HASH
Maintenance source root: $MaintenanceSourceRoot
Inno child runtime SHA256: $($runtime.sha256)
Upgrade helper SHA256: $upgradeHelperHash
Uninstall helper SHA256: $uninstallHelperHash

SECURITY BOUNDARY
-----------------
The Russian CryptoPro/Rutoken detached signature was verified on the governed Arvectum
release/owner station. This endpoint revalidates that immutable signing-evidence record
and exact release bytes; it does not need CryptoPro CSP or a Rutoken.

The maintenance helper identities are sealed release constants. Their bytes come from
explicit governed release-source material for release-policy commit $ExpectedReleaseCommit
and must match their canonical SHA256 values exactly. The production portable ZIP is
not treated as a source for installer maintenance helpers.

This pack does NOT disable Smart App Control, App Control for Business, Defender,
script enforcement, or any other Windows protection. It does NOT deploy itself.
Exact hash trust is release-specific; changed bytes require a regenerated pack.

CUSTOMER IT PREREQUISITES
-------------------------
1. Use an organization-managed App Control for Business base policy.
2. Ensure the base policy permits supplemental policies (rule option 17).
3. If the base policy is signed, configure authorized supplemental policy signers.
4. Validate the supplemental policy on representative devices before broad deployment.
5. Deploy the generated .cip through the customer's approved management path.

DO NOT
------
- Do not install CryptoPro CSP merely to run Arvectum Proxy Launcher.
- Do not run CiTool --update-policy from this generator.
- Do not turn Smart App Control off to make the unsigned EXE run.
- Do not disable script enforcement to make release helper scripts run.
- Do not treat the detached Russian signature as Microsoft Authenticode trust.
"@
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'DEPLOYMENT.txt') -Value $deployment -Encoding UTF8
    $checksums = @(Get-ChildItem -LiteralPath $OutputDirectory -File | Sort-Object Name | ForEach-Object { "$(Get-Sha256 $_.FullName)  $($_.Name)" })
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Value $checksums -Encoding ASCII
    Write-Host "Trust pack: $OutputDirectory"
    Write-Host "Policy XML: $policyXml"
    Write-Host "Policy CIP: $policyCip"
    Write-Host 'Deployment: NOT PERFORMED'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}