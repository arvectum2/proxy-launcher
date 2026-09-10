<#
.SYNOPSIS
    Generate a Russian-first App Control for Business trust pack for APL-WIN-014.
.DESCRIPTION
    Verifies the exact v0.2.3-ru.2 Russian release, then generates a customer-IT
    supplemental App Control policy using exact hash rules. The script never deploys
    a policy and never changes Smart App Control/App Control state on the machine.

    BootstrapHash mode covers the exact production Setup, application EXE, the exact
    upgrade/uninstall maintenance scripts, and the exact Inno Setup 6.7.1 child runtime
    derived from that production Setup.
    ReferenceFullHash mode additionally scans an exact installed reference tree so
    generated maintenance binaries (for example the Inno uninstaller) can be covered.

    Script enforcement remains enabled. Exact release maintenance scripts are included
    by hash so PowerShell can run those trusted files in FullLanguage while unrelated
    scripts and interactive PowerShell remain constrained by the customer base policy.
    Trusted child .ps1 files are invoked with the PowerShell call operator so Windows
    PowerShell 5.1 does not dot-source them through its -File command-line semantics.

    The target organization's existing App Control base policy must permit supplemental
    policies. Deployment remains an explicit customer-IT action.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory,

    [Parameter(Mandatory = $true)]
    [Guid]$BasePolicyId,

    [ValidateSet('BootstrapHash','ReferenceFullHash')]
    [string]$Mode = 'BootstrapHash',

    [string]$InstalledRoot = '',

    [string]$InnoRuntimePath = 'C:\Arvectum\Evidence\APL-WIN-014\runtime\inno-setup-6.7.1-runtime-stub.exe',

    [string]$InnoRuntimeEvidencePath = 'C:\Arvectum\Evidence\APL-WIN-014\runtime\production-runtime-extraction.json',

    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'APL-WIN-014 enterprise trust-pack generation must run on Windows.'
}

$ExpectedVersion = '0.2.3'
$ExpectedReleaseTag = 'v0.2.3-ru.2'
$ExpectedReleaseCommit = '47823585c42da54ab51dc2246583dc24d74d4ba6'
$ExpectedSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
$ExpectedPortableSha256 = '62d313547b4d8c2c8e6951d6cd866bb954fdf199ad7650063c8ed3bfbc455801'
$ExpectedAppSha256 = 'f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a'
$ExpectedSignerThumbprint = 'EE1CFA955BA22F03C39C76B183D94CD37494582E'
$ExpectedTrustSchema = 'arvectum.proxy.windows-app-control-enterprise-trust-pack.v1'
$MaintenanceScriptNames = @('upgrade_helper.ps1','uninstall_helper.ps1')

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-Command([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { throw "Required Windows command/cmdlet is unavailable: $Name" }
}

function Invoke-ReleaseVerifier([string]$Verifier, [string]$Directory) {
    $oldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        & $Verifier -ReleaseDirectory $Directory -ExpectedSignerThumbprint $ExpectedSignerThumbprint | Out-Host
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
    if ($exitCode -ne 0) { throw "Russian release verification failed with exit code $exitCode" }
}

function Get-PolicyIdFromXml([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $match = [regex]::Match($text, '<PolicyID>\s*([^<]+)\s*</PolicyID>', 'IgnoreCase')
    if (-not $match.Success) { throw 'Generated App Control policy has no PolicyID.' }
    return $match.Groups[1].Value.Trim()
}

function Get-OnePortableFile([string]$Root, [string]$Name) {
    $matches = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $Name)
    if ($matches.Count -ne 1) {
        throw "Portable archive must contain exactly one $Name; found $($matches.Count)."
    }
    return $matches[0].FullName
}

function Invoke-RuntimeMaterialValidator(
    [string]$Validator,
    [string]$RuntimePath,
    [string]$RuntimeEvidencePath,
    [string]$ExpectedSetupSha256
) {
    try {
        $output = @(
            & $Validator `
                -RuntimePath $RuntimePath `
                -RuntimeEvidencePath $RuntimeEvidencePath `
                -ExpectedSetupSha256 $ExpectedSetupSha256 `
                -AsJson
        )
    }
    catch {
        throw "Inno runtime validation command failed: $($_.Exception.Message)"
    }

    $json = ($output | Out-String).Trim()
    if (-not $json) {
        throw 'Inno runtime validation command returned no JSON evidence.'
    }

    try {
        return ($json | ConvertFrom-Json)
    }
    catch {
        throw "Inno runtime validation command returned invalid JSON: $($_.Exception.Message)"
    }
}

$runtimeHelper = Join-Path $PSScriptRoot 'windows_app_control_inno_runtime_material.ps1'
if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) { throw "Inno runtime validation helper is missing: $runtimeHelper" }

$ReleaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$setup = Join-Path $ReleaseDirectory 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe'
$portable = Join-Path $ReleaseDirectory 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-portable.zip'
$verifier = Join-Path $ReleaseDirectory 'verify_russian_release.ps1'

foreach ($required in @($setup, $portable, $verifier)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required production release input is missing: $required"
    }
}

$setupHash = Get-Sha256 $setup
$portableHash = Get-Sha256 $portable
if ($setupHash -ne $ExpectedSetupSha256) { throw 'Production installer SHA256 mismatch.' }
if ($portableHash -ne $ExpectedPortableSha256) { throw 'Production portable ZIP SHA256 mismatch.' }
$runtime = Invoke-RuntimeMaterialValidator `
    -Validator $runtimeHelper `
    -RuntimePath $InnoRuntimePath `
    -RuntimeEvidencePath $InnoRuntimeEvidencePath `
    -ExpectedSetupSha256 $ExpectedSetupSha256

Write-Host '=== APL-WIN-014 Russian release verification ==='
Invoke-ReleaseVerifier -Verifier $verifier -Directory $ReleaseDirectory

Assert-Command 'New-CIPolicy'
Assert-Command 'Set-CIPolicyIdInfo'
Assert-Command 'Set-CIPolicyVersion'
Assert-Command 'ConvertFrom-CIPolicy'

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $PWD ("out\app-control-trust-pack-$ExpectedVersion-$Mode")
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) {
    throw "Output directory already exists; refusing to overwrite a prior trust pack: $OutputDirectory"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$tempRoot = Join-Path $env:TEMP ("ArvectumAppControlPack-" + [guid]::NewGuid().ToString('N'))
$portableExtract = Join-Path $tempRoot 'portable'
$scanRoot = Join-Path $tempRoot 'scan'
New-Item -ItemType Directory -Path $portableExtract -Force | Out-Null
New-Item -ItemType Directory -Path $scanRoot -Force | Out-Null

try {
    Expand-Archive -LiteralPath $portable -DestinationPath $portableExtract -Force

    $appExe = Get-OnePortableFile -Root $portableExtract -Name 'Arvectum Proxy Launcher.exe'
    $portableManifestPath = Get-OnePortableFile -Root $portableExtract -Name 'build_manifest.json'
    $upgradeHelper = Get-OnePortableFile -Root $portableExtract -Name 'upgrade_helper.ps1'
    $uninstallHelper = Get-OnePortableFile -Root $portableExtract -Name 'uninstall_helper.ps1'

    $appHash = Get-Sha256 $appExe
    if ($appHash -ne $ExpectedAppSha256) { throw 'Portable application EXE SHA256 mismatch.' }

    $portableManifest = Get-Content -LiteralPath $portableManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $upgradeHelperHash = Get-Sha256 $upgradeHelper
    $uninstallHelperHash = Get-Sha256 $uninstallHelper
    if (-not $portableManifest.PSObject.Properties['upgrade_helper_sha256'] -or
        ([string]$portableManifest.upgrade_helper_sha256).ToLowerInvariant() -ne $upgradeHelperHash) {
        throw 'Portable upgrade_helper.ps1 SHA256 does not match build_manifest.json.'
    }
    if (-not $portableManifest.PSObject.Properties['uninstall_helper_sha256'] -or
        ([string]$portableManifest.uninstall_helper_sha256).ToLowerInvariant() -ne $uninstallHelperHash) {
        throw 'Portable uninstall_helper.ps1 SHA256 does not match build_manifest.json.'
    }

    Copy-Item -LiteralPath $setup -Destination (Join-Path $scanRoot 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe') -Force
    Copy-Item -LiteralPath $appExe -Destination (Join-Path $scanRoot 'Arvectum Proxy Launcher.exe') -Force
    Copy-Item -LiteralPath $upgradeHelper -Destination (Join-Path $scanRoot 'upgrade_helper.ps1') -Force
    Copy-Item -LiteralPath $uninstallHelper -Destination (Join-Path $scanRoot 'uninstall_helper.ps1') -Force

    $runtimeStage = Join-Path $scanRoot $runtime.filename
    Copy-Item -LiteralPath $runtime.path -Destination $runtimeStage -Force
    if ((Get-Sha256 $runtimeStage) -ne $runtime.sha256) { throw 'Staged Inno runtime bytes drifted before ConfigCI policy authoring.' }

    $referenceFiles = @()
    if ($Mode -eq 'ReferenceFullHash') {
        if (-not $InstalledRoot) {
            $documents = [Environment]::GetFolderPath('MyDocuments')
            $InstalledRoot = Join-Path $documents 'ArvectumProxyLauncher'
        }
        $InstalledRoot = (Resolve-Path -LiteralPath $InstalledRoot).Path
        $installedExe = Join-Path $InstalledRoot 'Arvectum Proxy Launcher.exe'
        if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) {
            throw "Reference installation launcher is missing: $installedExe"
        }
        if ((Get-Sha256 $installedExe) -ne $ExpectedAppSha256) {
            throw 'Reference installation does not contain the exact sealed application EXE.'
        }
        $repairSetup = Join-Path $InstalledRoot 'Arvectum Proxy Launcher Repair.exe'
        if (-not (Test-Path -LiteralPath $repairSetup -PathType Leaf)) {
            throw 'Reference installation cached repair Setup is missing.'
        }
        if ((Get-Sha256 $repairSetup) -ne $ExpectedSetupSha256) {
            throw 'Reference cached repair Setup does not match the exact production installer.'
        }

        $installedUpgrade = Join-Path $InstalledRoot 'upgrade_helper.ps1'
        $installedUninstall = Join-Path $InstalledRoot 'uninstall_helper.ps1'
        if (-not (Test-Path -LiteralPath $installedUpgrade -PathType Leaf) -or (Get-Sha256 $installedUpgrade) -ne $upgradeHelperHash) {
            throw 'Reference installation upgrade_helper.ps1 does not match the sealed release helper.'
        }
        if (-not (Test-Path -LiteralPath $installedUninstall -PathType Leaf) -or (Get-Sha256 $installedUninstall) -ne $uninstallHelperHash) {
            throw 'Reference installation uninstall_helper.ps1 does not match the sealed release helper.'
        }

        $referenceStage = Join-Path $scanRoot 'installed-reference-tree'
        Copy-Item -LiteralPath $InstalledRoot -Destination $referenceStage -Recurse -Force
        $referenceFiles = @(
            Get-ChildItem -LiteralPath $InstalledRoot -File -Recurse -Force | ForEach-Object {
                [ordered]@{
                    relative_path = $_.FullName.Substring($InstalledRoot.Length).TrimStart('\')
                    sha256 = Get-Sha256 $_.FullName
                    size = [long]$_.Length
                }
            }
        )
    }

    $policyXml = Join-Path $OutputDirectory 'Arvectum-Proxy-Launcher-AppControl-Supplemental.xml'
    $policyName = "Arvectum Proxy Launcher $ExpectedVersion Exact Hash"

    Write-Host '=== Generating exact-hash App Control policy ==='
    New-CIPolicy -MultiplePolicyFormat -ScanPath $scanRoot -UserPEs -NoShadowCopy -FilePath $policyXml -Level Hash | Out-Null

    $policyXmlText = Get-Content -LiteralPath $policyXml -Raw -Encoding UTF8
    if ($policyXmlText -match 'Disabled:Script Enforcement') {
        throw 'Generated product supplemental policy disables script enforcement; refusing unsafe trust pack.'
    }
    foreach ($scriptName in $MaintenanceScriptNames) {
        if ($policyXmlText -notmatch [regex]::Escape($scriptName)) {
            throw "Generated product supplemental policy is missing exact script rules for $scriptName."
        }
    }

    Set-CIPolicyIdInfo -FilePath $policyXml -ResetPolicyID -PolicyName $policyName -SupplementsBasePolicyID $BasePolicyId | Out-Null
    Set-CIPolicyVersion -FilePath $policyXml -Version '0.2.3.0'

    $policyId = Get-PolicyIdFromXml $policyXml
    $policyFileSafe = $policyId.Trim('{}')
    $policyCip = Join-Path $OutputDirectory ("{$policyFileSafe}.cip")
    ConvertFrom-CIPolicy -XmlFilePath $policyXml -BinaryFilePath $policyCip
    if (-not (Test-Path -LiteralPath $policyCip -PathType Leaf)) {
        throw 'ConfigCI did not create the binary supplemental policy.'
    }

    $authSetup = Get-AuthenticodeSignature -LiteralPath $setup
    $authApp = Get-AuthenticodeSignature -LiteralPath $appExe

    $manifest = [ordered]@{
        schema = $ExpectedTrustSchema
        task = 'APL-WIN-014'
        created_utc = [DateTime]::UtcNow.ToString('o')
        version = $ExpectedVersion
        release_tag = $ExpectedReleaseTag
        release_commit = $ExpectedReleaseCommit
        russian_release_verification = 'PASS'
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
        policy_scope = $(if ($Mode -eq 'BootstrapHash') {
            'exact production Setup + exact production application EXE + exact upgrade/uninstall maintenance scripts + exact Inno Setup 6.7.1 child runtime derived from that Setup'
        } else {
            'exact production Setup + complete exact reference installation tree including generated maintenance binaries + exact upgrade/uninstall maintenance scripts + exact Inno Setup 6.7.1 child runtime derived from that Setup'
        })
        reference_files = $referenceFiles
        deployment_invariants = @(
            'pack generation never deploys App Control policy',
            'customer base policy must allow supplemental policies',
            'Smart App Control must not be disabled as a workaround',
            'script enforcement remains enabled; only exact release maintenance scripts are allowed by hash',
            'hash policy is release-specific and must be regenerated for changed bytes',
            'Inno child runtime trust is bound to exact runtime bytes statically derived from the exact production Setup and independently behaviorally cross-validated',
            'Russian detached release provenance remains independently verified'
        )
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
Inno child runtime SHA256: $($runtime.sha256)
Upgrade helper SHA256: $upgradeHelperHash
Uninstall helper SHA256: $uninstallHelperHash

SECURITY BOUNDARY
-----------------
This pack does NOT disable Smart App Control, App Control for Business, Defender,
script enforcement, or any other Windows protection. It does NOT deploy itself.

The Russian CryptoPro/Rutoken detached signature proves release-set provenance and
integrity. It is separate from Windows execution trust.

The Inno child setup runtime is trusted only by its exact hash. Its bytes are statically
derived from the exact production Setup and must match the independently behaviorally
validated Inno Setup 6.7.1 runtime anchor.

The release maintenance PowerShell scripts are also trusted only by exact hash. This is
required because the sealed Inno installer invokes upgrade_helper.ps1 and uninstall
invokes uninstall_helper.ps1. Script enforcement remains active for unrelated scripts.

CUSTOMER IT PREREQUISITES
-------------------------
1. Use an organization-managed App Control for Business base policy.
2. Ensure the base policy permits supplemental policies (rule option 17).
3. If the base policy is signed, configure authorized supplemental policy signers.
4. Validate this supplemental policy in Audit mode / representative test devices first.
5. Deploy the generated .cip only through the customer's approved management path.

HASH POLICY CHARACTERISTICS
---------------------------
Hash trust is exact-byte trust. Any new Arvectum release, rebuilt EXE, installer,
uninstaller, child setup runtime, maintenance script, or maintenance binary with changed
bytes requires a regenerated pack.

BootstrapHash is suitable only as a bootstrap allow-list for the exact Setup, app EXE,
maintenance scripts, and Inno child runtime. For full lifecycle coverage use either:
  - ReferenceFullHash, generated from an exact isolated reference installation; or
  - the customer's approved Managed Installer deployment model.

MANAGED INSTALLER PROFILE
-------------------------
For Intune / Configuration Manager / another customer-governed distribution system,
Managed Installer can reduce per-release policy churn when the customer's security
model accepts its heuristic trust boundary. Customer IT must designate and govern the
managed installer. Updates must also be deployed through that managed installer or be
separately authorized; self-updated/generated binaries are not assumed trusted.
Arvectum supplies exact release verification evidence and hashes and never designates
itself as a managed installer.

DO NOT
------
- Do not run CiTool --update-policy from this generator.
- Do not turn Smart App Control off to make the unsigned EXE run.
- Do not disable script enforcement to make release helper scripts run.
- Do not treat the detached Russian signature as Microsoft Authenticode trust.
- Do not deploy a supplemental policy against an unknown or unauthorized base policy.
"@
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'DEPLOYMENT.txt') -Value $deployment -Encoding UTF8

    $checksums = @(
        Get-ChildItem -LiteralPath $OutputDirectory -File | Sort-Object Name | ForEach-Object {
            "$(Get-Sha256 $_.FullName)  $($_.Name)"
        }
    )
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Value $checksums -Encoding ASCII

    $manifest.result = 'PASS'
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Write-Host "Trust pack: $OutputDirectory"
    Write-Host "Policy XML: $policyXml"
    Write-Host "Policy CIP: $policyCip"
    Write-Host 'Deployment: NOT PERFORMED'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
