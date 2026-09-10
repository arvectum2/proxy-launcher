<#
.SYNOPSIS
    Fail-closed verification that an APL-WIN-014 ReferenceFullHash trust pack
    contains the exact accepted Inno Setup 6.7.1 child runtime hash rules.
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
$ExpectedAnchorRun = 33669452947

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
if (([string]$runtime.sha256).ToLowerInvariant() -ne $ExpectedRuntimeSha256) { throw 'Runtime trust verification: runtime SHA256 mismatch.' }
if (([string]$runtime.crc32).ToLowerInvariant() -ne $ExpectedRuntimeCrc32) { throw 'Runtime trust verification: runtime CRC32 mismatch.' }
if (([string]$runtime.source_setup_sha256).ToLowerInvariant() -ne $ExpectedSetupSha256) { throw 'Runtime trust verification: runtime was not derived from the canonical production Setup.' }
if ([string]$runtime.official_inno_tag -ne $ExpectedInnoTag -or [string]$runtime.official_inno_commit -ne $ExpectedInnoCommit) { throw 'Runtime trust verification: Inno source provenance mismatch.' }
if ([long]$runtime.behavioral_anchor_workflow_run -ne $ExpectedAnchorRun -or [string]$runtime.static_to_behavioral_anchor -ne 'PASS') { throw 'Runtime trust verification: static/behavioral anchor is not PASS.' }

$xmlName = [string]$manifest.supplemental_policy_xml
$cipName = [string]$manifest.supplemental_policy_cip
if (-not $xmlName -or -not $cipName) { throw 'Runtime trust verification: supplemental policy filenames are missing.' }
$xmlPath = Join-Path $TrustPackDirectory $xmlName
$cipPath = Join-Path $TrustPackDirectory $cipName
if (-not (Test-Path -LiteralPath $xmlPath -PathType Leaf) -or -not (Test-Path -LiteralPath $cipPath -PathType Leaf)) { throw 'Runtime trust verification: supplemental XML/CIP is missing.' }

$xmlText = Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8
$escapedRuntime = [regex]::Escape($ExpectedRuntimeFilename)
$ruleMatches = [regex]::Matches($xmlText, '<Allow\b[^>]*\bFriendlyName="([^"]*' + $escapedRuntime + ' Hash ([^"]+))"[^>]*\bHash="([0-9A-Fa-f]+)"[^>]*/?>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
if ($ruleMatches.Count -ne 4) { throw "Runtime trust verification: expected exactly 4 runtime hash rules, found $($ruleMatches.Count)." }
$variants = @()
$fullSha256Matches = @()
foreach ($match in $ruleMatches) {
    $variant = [string]$match.Groups[2].Value
    $variants += $variant
    if ($variant -ieq 'Sha256') { $fullSha256Matches += $match }
}
$expectedVariants = @('Sha1','Sha256','Page Sha1','Page Sha256')
foreach ($expected in $expectedVariants) {
    if (@($variants | Where-Object { $_ -ieq $expected }).Count -ne 1) { throw "Runtime trust verification: missing/duplicate runtime hash variant: $expected" }
}
if ($fullSha256Matches.Count -ne 1 -or ([string]$fullSha256Matches[0].Groups[3].Value).ToLowerInvariant() -ne $ExpectedRuntimeSha256) {
    throw 'Runtime trust verification: full-file runtime Sha256 rule does not equal the accepted runtime hash.'
}

Write-Host 'APL-WIN-014 Inno runtime trust-pack verification: PASS'
Write-Host "Runtime SHA256: $ExpectedRuntimeSha256"
Write-Host 'Runtime hash variants: Sha1 / Sha256 / Page Sha1 / Page Sha256: PASS'
