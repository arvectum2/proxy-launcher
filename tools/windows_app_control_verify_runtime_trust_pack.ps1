<#
.SYNOPSIS
    Fail-closed verification that an APL-WIN-014 ReferenceFullHash trust pack
    contains the exact accepted Inno Setup 6.7.1 child runtime hash rules.
.DESCRIPTION
    The manifest binds the exact runtime bytes by flat SHA256/CRC32. ConfigCI policy
    rules are verified separately because App Control Hash rules use Authenticode/PE
    image hashes rather than the ordinary flat-file SHA256.
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
$ExpectedBehavioralRun = 33666343748

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
if ([long]$runtime.behavioral_anchor_workflow_run -ne $ExpectedBehavioralRun -or [string]$runtime.static_to_behavioral_anchor -ne 'PASS') { throw 'Runtime trust verification: static/behavioral anchor is not PASS.' }

$xmlName = [string]$manifest.supplemental_policy_xml
$cipName = [string]$manifest.supplemental_policy_cip
if (-not $xmlName -or -not $cipName) { throw 'Runtime trust verification: supplemental policy filenames are missing.' }
$xmlPath = Join-Path $TrustPackDirectory $xmlName
$cipPath = Join-Path $TrustPackDirectory $cipName
if (-not (Test-Path -LiteralPath $xmlPath -PathType Leaf) -or -not (Test-Path -LiteralPath $cipPath -PathType Leaf)) { throw 'Runtime trust verification: supplemental XML/CIP is missing.' }

$lines = @(Get-Content -LiteralPath $xmlPath -Encoding UTF8)
$runtimeRules = @()
foreach ($line in $lines) {
    if ($line -notmatch '<Allow\s+[^>]*\bID="([^"]+)"[^>]*\bFriendlyName="([^"]+)"[^>]*\bHash="([0-9A-Fa-f]+)"') { continue }
    $id = [string]$matches[1]
    $friendlyName = [string]$matches[2]
    $hash = [string]$matches[3]
    $leaf = $friendlyName -replace '^.*[\\/]', ''
    if ($leaf -notlike "$ExpectedRuntimeFilename Hash *") { continue }
    $variant = $leaf -replace ('^' + [regex]::Escape($ExpectedRuntimeFilename) + ' Hash '), ''
    $runtimeRules += [pscustomobject]@{ id=$id; variant=$variant; hash=$hash }
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

Write-Host 'APL-WIN-014 Inno runtime trust-pack verification: PASS'
Write-Host "Runtime flat SHA256: $ExpectedRuntimeSha256"
Write-Host 'ConfigCI Authenticode/PE hash variants: Sha1 / Sha256 / Page Sha1 / Page Sha256: PASS'
Write-Host 'Runtime FileRuleRefs in UMCI SigningScenario 12: PASS'
