<#
.SYNOPSIS
    Fail-closed verification that an APL-WIN-014 ReferenceFullHash trust pack
    contains the exact accepted Inno Setup 6.7.1 child runtime hash rules and
    exact maintenance-script rules without disabling App Control script enforcement.
.DESCRIPTION
    The manifest binds the exact runtime bytes by flat SHA256/CRC32. ConfigCI policy
    rules are verified separately because App Control Hash rules use Authenticode/PE
    image hashes rather than the ordinary flat-file SHA256 for PE files.

    The verifier also requires upgrade_helper.ps1 and uninstall_helper.ps1 to be
    explicitly present in the product policy and rejects rule option 11
    Disabled:Script Enforcement. This keeps unrelated PowerShell constrained while
    exact release maintenance scripts may run as trusted files.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TrustPackDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedSchema = 'arvectum.proxy.windows-app-control-enterprise-trust-pack.v1'
$ExpectedMode = 'ReferenceFullHash'
$ExpectedSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
$ExpectedRuntimeFilename = 'inno-setup-6.7.1-runtime-stub.exe'
$ExpectedRuntimeSize = 4473344
$ExpectedRuntimeSha256 = 'b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8'
$ExpectedRuntimeCrc32 = '021edadf'
$ExpectedInnoTag = 'is-6_7_1'
$ExpectedInnoCommit = 'cfdf48923178df4b4f040e038b423aa555a61ffc'
$ExpectedEvidenceRun = 33669452947
$ExpectedBehavioralRun = 33666343748
$ExpectedHistoricalAnchorSetupSha256 = '7e7640fe434067415840a154cfbeba0df443caf155fed38cff7ede1bc7d7d600'
$ExpectedMaintenanceScripts = @('upgrade_helper.ps1','uninstall_helper.ps1')

$TrustPackDirectory = (Resolve-Path -LiteralPath $TrustPackDirectory).Path
$manifestPath = Join-Path $TrustPackDirectory 'trust-pack.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Runtime trust verification: trust-pack.json is missing.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$manifest.schema -ne $ExpectedSchema -or [string]$manifest.mode -ne $ExpectedMode -or [string]$manifest.result -eq 'BLOCK') {
    throw 'Runtime trust verification: manifest is not the canonical ReferenceFullHash trust pack.'
}
if (-not $manifest.PSObject.Properties['inno_runtime']) { throw 'Runtime trust verification: manifest has no inno_runtime evidence.' }
$runtime = $manifest.inno_runtime
if (-not [bool]$runtime.hash_policy_integrated) { throw 'Runtime trust verification: runtime hash integration is not asserted.' }
if ([string]$runtime.filename -ne $ExpectedRuntimeFilename) { throw 'Runtime trust verification: runtime filename mismatch.' }
if ([long]$runtime.size -ne $ExpectedRuntimeSize) { throw 'Runtime trust verification: runtime size mismatch.' }
if (([string]$runtime.sha256).ToLowerInvariant() -ne $ExpectedRuntimeSha256) { throw 'Runtime trust verification: runtime flat SHA256 mismatch.' }
if (([string]$runtime.crc32).ToLowerInvariant() -ne $ExpectedRuntimeCrc32) { throw 'Runtime trust verification: runtime CRC32 mismatch.' }
if (([string]$runtime.source_setup_sha256).ToLowerInvariant() -ne $ExpectedSetupSha256) { throw 'Runtime trust verification: runtime was not derived from the canonical production Setup.' }
if ([string]$runtime.official_inno_tag -ne $ExpectedInnoTag -or [string]$runtime.official_inno_commit -ne $ExpectedInnoCommit) { throw 'Runtime trust verification: Inno source provenance mismatch.' }
if ([long]$runtime.evidence_workflow_run -ne $ExpectedEvidenceRun) { throw 'Runtime trust verification: static evidence workflow provenance mismatch.' }
if ([long]$runtime.behavioral_workflow_run -ne $ExpectedBehavioralRun) { throw 'Runtime trust verification: behavioral workflow provenance mismatch.' }
if (([string]$runtime.historical_anchor_setup_sha256).ToLowerInvariant() -ne $ExpectedHistoricalAnchorSetupSha256) { throw 'Runtime trust verification: historical static/behavioral anchor Setup mismatch.' }
if ([string]$runtime.static_to_behavioral_anchor -ne 'PASS') { throw 'Runtime trust verification: static/behavioral anchor is not PASS.' }

if (-not $manifest.PSObject.Properties['script_enforcement_preserved'] -or -not [bool]$manifest.script_enforcement_preserved) {
    throw 'Runtime trust verification: manifest does not assert preserved script enforcement.'
}
if (-not $manifest.PSObject.Properties['maintenance_scripts']) {
    throw 'Runtime trust verification: manifest has no maintenance_scripts evidence.'
}
$maintenanceManifest = @($manifest.maintenance_scripts)
if ($maintenanceManifest.Count -ne $ExpectedMaintenanceScripts.Count) {
    throw 'Runtime trust verification: maintenance_scripts evidence count mismatch.'
}
foreach ($scriptName in $ExpectedMaintenanceScripts) {
    $records = @($maintenanceManifest | Where-Object { [string]$_.filename -ceq $scriptName })
    if ($records.Count -ne 1) { throw "Runtime trust verification: missing/duplicate maintenance script manifest entry: $scriptName" }
    if ([string]$records[0].sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "Runtime trust verification: malformed maintenance script SHA256: $scriptName" }

    $referenceRecords = @($manifest.reference_files | Where-Object { ([string]$_.relative_path).TrimStart('\') -ceq $scriptName })
    if ($referenceRecords.Count -ne 1) { throw "Runtime trust verification: reference tree missing/duplicates maintenance script: $scriptName" }
    if (([string]$referenceRecords[0].sha256).ToLowerInvariant() -ne ([string]$records[0].sha256).ToLowerInvariant()) {
        throw "Runtime trust verification: reference maintenance script hash drift: $scriptName"
    }
}

$xmlName = [string]$manifest.supplemental_policy_xml
$cipName = [string]$manifest.supplemental_policy_cip
if (-not $xmlName -or -not $cipName) { throw 'Runtime trust verification: supplemental policy filenames are missing.' }
$xmlPath = Join-Path $TrustPackDirectory $xmlName
$cipPath = Join-Path $TrustPackDirectory $cipName
if (-not (Test-Path -LiteralPath $xmlPath -PathType Leaf) -or -not (Test-Path -LiteralPath $cipPath -PathType Leaf)) { throw 'Runtime trust verification: supplemental XML/CIP is missing.' }

$lines = @(Get-Content -LiteralPath $xmlPath -Encoding UTF8)
if (@($lines | Where-Object { $_ -match 'Disabled:Script Enforcement' }).Count -ne 0) {
    throw 'Runtime trust verification: product supplemental policy disables App Control script enforcement.'
}

$allAllowRules = @()
foreach ($line in $lines) {
    if ($line -notmatch '<Allow\s+[^>]*\bID="([^"]+)"[^>]*\bFriendlyName="([^"]+)"[^>]*\bHash="([0-9A-Fa-f]+)"') { continue }
    $allAllowRules += [pscustomobject]@{
        id = [string]$matches[1]
        friendly_name = [string]$matches[2]
        hash = [string]$matches[3]
    }
}

$runtimeRules = @()
foreach ($rule in $allAllowRules) {
    $leaf = $rule.friendly_name -replace '^.*[\\/]', ''
    if ($leaf -notlike "$ExpectedRuntimeFilename Hash *") { continue }
    $variant = $leaf -replace ('^' + [regex]::Escape($ExpectedRuntimeFilename) + ' Hash '), ''
    $runtimeRules += [pscustomobject]@{ id=$rule.id; variant=$variant; hash=$rule.hash }
}

if ($runtimeRules.Count -ne 4) { throw "Runtime trust verification: expected exactly 4 runtime Authenticode/PE hash rules, found $($runtimeRules.Count)." }
$expectedVariants = @{
    'Sha1' = 40
    'Sha256' = 64
    'Page Sha1' = 40
    'Page Sha256' = 64
}
foreach ($expected in $expectedVariants.Keys) {
    $matchesForVariant = @($runtimeRules | Where-Object { $_.variant -ceq $expected })
    if ($matchesForVariant.Count -ne 1) { throw "Runtime trust verification: missing/duplicate runtime hash variant: $expected" }
    if ([string]$matchesForVariant[0].hash -notmatch ('^[0-9A-Fa-f]{' + $expectedVariants[$expected] + '}$')) { throw "Runtime trust verification: malformed ConfigCI hash for variant: $expected" }
}
if (@($runtimeRules.id | Sort-Object -Unique).Count -ne 4) { throw 'Runtime trust verification: runtime hash rule IDs are not unique.' }

$maintenanceRules = @{}
foreach ($scriptName in $ExpectedMaintenanceScripts) {
    $rules = @($allAllowRules | Where-Object {
        $leaf = $_.friendly_name -replace '^.*[\\/]', ''
        $leaf -like "$scriptName Hash *"
    })
    if ($rules.Count -eq 0) {
        throw "Runtime trust verification: maintenance script has no App Control hash rule: $scriptName"
    }
    $maintenanceRules[$scriptName] = $rules
}

$userRefs = @()
$inUserScenario = $false
foreach ($line in $lines) {
    if ($line -match '<SigningScenario\b[^>]*\bValue="12"') { $inUserScenario = $true }
    if ($inUserScenario -and $line -match '<FileRuleRef\s+RuleID="([^"]+)"') { $userRefs += [string]$matches[1] }
    if ($line -match '</SigningScenario>') { $inUserScenario = $false }
}
foreach ($rule in $runtimeRules) {
    if (@($userRefs | Where-Object { $_ -ceq $rule.id }).Count -ne 1) { throw "Runtime trust verification: runtime rule is not bound exactly once into UMCI SigningScenario 12: $($rule.id)" }
}
foreach ($scriptName in $ExpectedMaintenanceScripts) {
    foreach ($rule in @($maintenanceRules[$scriptName])) {
        if (@($userRefs | Where-Object { $_ -ceq $rule.id }).Count -ne 1) {
            throw "Runtime trust verification: maintenance script rule is not bound exactly once into UMCI SigningScenario 12: $scriptName / $($rule.id)"
        }
    }
}

Write-Host 'APL-WIN-014 Inno runtime trust-pack verification: PASS'
Write-Host "Runtime flat SHA256: $ExpectedRuntimeSha256"
Write-Host "Static evidence workflow: $ExpectedEvidenceRun"
Write-Host "Behavioral workflow: $ExpectedBehavioralRun"
Write-Host 'ConfigCI Authenticode/PE hash variants: Sha1 / Sha256 / Page Sha1 / Page Sha256: PASS'
Write-Host 'Runtime FileRuleRefs in UMCI SigningScenario 12: PASS'
Write-Host 'Maintenance script exact-hash rules in UMCI SigningScenario 12: PASS'
Write-Host 'App Control script enforcement preserved: PASS'
