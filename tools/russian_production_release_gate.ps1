<#
.SYNOPSIS
    Fail-closed Russian production publication gate for APL-REL-013.
.DESCRIPTION
    Validates the exact final Russian release set after APL-REL-011 signing and
    APL-REL-012 consumer verification. It also requires the signed APL-REL-014
    exact lifecycle/recovery evidence, a negative tamper test, exact Git
    provenance, and emits a non-secret PUBLISH decision outside the signed
    release directory. It never signs, stores a PIN, or exports a key.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$ReleaseDirectory,
    [Parameter(Mandatory = $true)] [string]$Version,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$')]
    [string]$GitTag,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$GitCommit,
    [string]$ExpectedSignerThumbprint = 'EE1CFA955BA22F03C39C76B183D94CD37494582E',
    [string]$DecisionOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'APL-REL-013 production release gate must run on Windows against the exact final Russian release set.'
}

function Normalize-Thumbprint([string]$Thumbprint) {
    return (($Thumbprint -replace '\s', '').ToUpperInvariant())
}

function Normalize-Sha256([object]$Value, [string]$Label) {
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -notmatch '^[0-9a-f]{64}$') { throw "$Label is not a SHA-256 value." }
    return $text
}

function Invoke-Git([string[]]$Arguments) {
    $output = & git @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code ${exitCode}: $($output -join ' ')"
    }
    return (($output | ForEach-Object { $_.ToString() }) -join "`n").Trim()
}

function Invoke-ReleaseVerifier([string]$Directory, [bool]$ExpectSuccess) {
    $scriptPath = Join-Path $Directory 'verify_russian_release.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Bundled REL-012 verifier is missing: $scriptPath"
    }

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ReleaseDirectory $Directory 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"

    if ($ExpectSuccess) {
        if ($exitCode -ne 0 -or $text -notmatch 'РЕЗУЛЬТАТ:\s*ПРОВЕРКА ПРОЙДЕНА') {
            throw "REL-012 verification did not PASS for the exact final release set. Exit=$exitCode"
        }
    }
    else {
        if ($exitCode -eq 0 -or $text -notmatch 'РЕЗУЛЬТАТ:\s*ПРОВЕРКА НЕ ПРОЙДЕНА') {
            throw 'Negative tamper test unexpectedly passed. Publication is forbidden.'
        }
    }
}

if (-not (Test-Path -LiteralPath $ReleaseDirectory -PathType Container)) {
    throw "Release directory does not exist: $ReleaseDirectory"
}
$releasePath = (Resolve-Path -LiteralPath $ReleaseDirectory).Path

if ($GitTag -notmatch ('^v' + [regex]::Escape($Version) + '(?:$|[-+])')) {
    throw "Version/tag mismatch: Version=$Version GitTag=$GitTag"
}

$rel014Name = 'apl-rel-014-lifecycle-evidence.json'
$required = @(
    'SHA256SUMS.txt',
    'SHA256SUMS.txt.sig',
    'signer-certificate.cer',
    'signing-evidence.json',
    'verify_russian_release.ps1',
    'VERIFY_RUSSIAN_RELEASE.cmd',
    $rel014Name
)
foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $releasePath $name) -PathType Leaf)) {
        throw "Required final-release file is missing: $name"
    }
}

$evidence = Get-Content -LiteralPath (Join-Path $releasePath 'signing-evidence.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($evidence.product -ne 'Arvectum Proxy Launcher') { throw 'Unexpected product in signing evidence.' }
if ($evidence.task -ne 'APL-REL-011') { throw 'Signing evidence was not produced by APL-REL-011.' }
if ($evidence.signing_mode -ne 'russian-qualified-evidence') { throw 'Unexpected signing mode.' }
if ([string]$evidence.version -ne $Version) { throw 'Version does not match signing evidence.' }
if ([string]$evidence.git_tag -ne $GitTag) { throw 'Git tag does not match signing evidence.' }
if (([string]$evidence.git_commit).ToLowerInvariant() -ne $GitCommit.ToLowerInvariant()) { throw 'Git commit does not match signing evidence.' }
if (-not [bool]$evidence.detached_signature_verified) { throw 'REL-011 evidence does not record successful detached verification.' }
if ([bool]$evidence.embedded_code_signing_activated) { throw 'Current Russia-first gate forbids an ungoverned embedded-code-signing claim.' }
if ([bool]$evidence.pin_stored) { throw 'Signing evidence reports PIN storage. Publication is forbidden.' }
if ([bool]$evidence.private_key_export_attempted) { throw 'Signing evidence reports a private-key export attempt. Publication is forbidden.' }

$expectedThumbprint = Normalize-Thumbprint $ExpectedSignerThumbprint
$evidenceThumbprint = Normalize-Thumbprint ([string]$evidence.signer_thumbprint)
if ($evidenceThumbprint -ne $expectedThumbprint) {
    throw "Signer thumbprint is not the governed ООО «Арвектум» release-evidence identity: $evidenceThumbprint"
}
if (([string]$evidence.signer_subject) -notmatch 'АРВЕКТУМ') {
    throw 'Signing evidence subject does not identify АРВЕКТУМ.'
}

# APL-REL-014: the lifecycle evidence itself must be a signed release asset,
# and its exact 0.2.4 product identities must match the repository contract.
$rel014Path = Join-Path $releasePath $rel014Name
$rel014 = Get-Content -LiteralPath $rel014Path -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$rel014.schema -ne 'arvectum.proxy.apl-rel-014-exact-evidence.v1') { throw 'Unexpected APL-REL-014 evidence schema.' }
if ([string]$rel014.task -ne 'APL-REL-014') { throw 'Lifecycle evidence was not produced by APL-REL-014.' }
if ([string]$rel014.product -ne 'Arvectum Proxy Launcher') { throw 'Unexpected product in APL-REL-014 evidence.' }
if ([string]$rel014.result -ne 'PASS') { throw 'APL-REL-014 lifecycle evidence is not PASS.' }
if ([string]$rel014.scope -ne 'EXACT_PRODUCT_SET_READY_FOR_REL011_SIGNING') { throw 'APL-REL-014 evidence scope is unexpected.' }
if ([string]$rel014.version -ne $Version) { throw 'APL-REL-014 version does not match the release version.' }
if ([string]$rel014.signed_set_binding.state -ne 'READY_FOR_REL011_SIGNING') { throw 'APL-REL-014 evidence was not finalized before REL-011 signing.' }
if (-not [bool]$rel014.signed_set_binding.rel013_post_sign_binding_required) { throw 'APL-REL-014 evidence does not require REL-013 post-sign binding.' }
if ([bool]$rel014.signed_set_binding.final_signed_set_pass_claimed) { throw 'APL-REL-014 pre-sign evidence improperly claims final signed-set PASS.' }
if ([string]$rel014.signed_set_binding.required_signing_mode -ne [string]$evidence.signing_mode) { throw 'APL-REL-014 signing mode does not match REL-011 evidence.' }
if ((Normalize-Thumbprint ([string]$rel014.signed_set_binding.required_signer_thumbprint)) -ne $expectedThumbprint) { throw 'APL-REL-014 requires a different signer identity.' }

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$rel014ContractPath = Join-Path $repoRoot 'release\APL_REL_014_EXACT_SIGNED_SET_CONTRACT.json'
if (-not (Test-Path -LiteralPath $rel014ContractPath -PathType Leaf)) { throw 'Repository APL-REL-014 exact-set contract is missing.' }
$rel014Contract = Get-Content -LiteralPath $rel014ContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$rel014Contract.schema -ne 'arvectum.proxy.apl-rel-014-exact-set-contract.v1') { throw 'Repository APL-REL-014 contract schema is unexpected.' }
if ([string]$rel014Contract.version -ne $Version) { throw 'Repository APL-REL-014 contract targets another version.' }
$contractHash = (Get-FileHash -LiteralPath $rel014ContractPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ((Normalize-Sha256 $rel014.source_evidence.contract_sha256 'APL-REL-014 contract hash') -ne $contractHash) { throw 'APL-REL-014 evidence was produced from a different exact-set contract.' }
if (([string]$rel014.candidate_source_commit).ToLowerInvariant() -ne ([string]$rel014Contract.candidate_source_commit).ToLowerInvariant()) { throw 'APL-REL-014 candidate source commit drifted from the repository contract.' }

$contractSetupHash = Normalize-Sha256 $rel014Contract.candidate.setup_sha256 'Contract Setup hash'
$contractPortableHash = Normalize-Sha256 $rel014Contract.candidate.portable_zip_sha256 'Contract portable hash'
$contractAppHash = Normalize-Sha256 $rel014Contract.candidate.application_sha256 'Contract application hash'
$rel014SetupHash = Normalize-Sha256 $rel014.release_assets.setup.sha256 'APL-REL-014 Setup hash'
$rel014PortableHash = Normalize-Sha256 $rel014.release_assets.portable_zip.sha256 'APL-REL-014 portable hash'
$rel014AppHash = Normalize-Sha256 $rel014.release_assets.application_inside_lifecycle.sha256 'APL-REL-014 application hash'
if ($rel014SetupHash -ne $contractSetupHash) { throw 'APL-REL-014 Setup hash drifted from the exact-set contract.' }
if ($rel014PortableHash -ne $contractPortableHash) { throw 'APL-REL-014 portable hash drifted from the exact-set contract.' }
if ($rel014AppHash -ne $contractAppHash) { throw 'APL-REL-014 application hash drifted from the exact-set contract.' }
if ((Normalize-Sha256 $rel014.predecessor.setup_sha256 'APL-REL-014 predecessor Setup hash') -ne (Normalize-Sha256 $rel014Contract.predecessor.setup_sha256 'Contract predecessor Setup hash')) { throw 'APL-REL-014 predecessor Setup hash drifted from contract.' }
if ((Normalize-Sha256 $rel014.predecessor.application_sha256 'APL-REL-014 predecessor application hash') -ne (Normalize-Sha256 $rel014Contract.predecessor.application_sha256 'Contract predecessor application hash')) { throw 'APL-REL-014 predecessor application hash drifted from contract.' }

foreach ($gateName in @('predecessor','upgrade','runtime','rollback','repair','uninstall')) {
    if ([string]$rel014.lifecycle.gates.$gateName -ne 'PASS') { throw "APL-REL-014 lifecycle gate is not PASS: $gateName" }
}
foreach ($gateName in @('before','after','code_integrity_3077')) {
    if ([string]$rel014.lifecycle.app_control.$gateName -ne 'PASS') { throw "APL-REL-014 App Control gate is not PASS: $gateName" }
}
if ([int]$rel014.lifecycle.code_integrity_3077_count -ne 0) { throw 'APL-REL-014 contains Code Integrity 3077 blocks.' }
if ([string]$rel014.lifecycle.runtime.auto_config_url -ne 'http://127.0.0.1:8082/proxy.pac') { throw 'APL-REL-014 PAC URL is unexpected.' }
if ([int]$rel014.lifecycle.runtime.pac_http_status -ne 200) { throw 'APL-REL-014 PAC HTTP status is not 200.' }

# The REL-014 evidence JSON, Setup, and portable ZIP must each be present in
# REL-011 signing evidence with exactly the hashes REL-014 proved.
$signedAssets = @($evidence.assets)
function Assert-SignedRel014Asset([string]$Name, [string]$ExpectedHash, [string]$Label) {
    $matches = @($signedAssets | Where-Object { ([string]$_.name) -ceq $Name })
    if ($matches.Count -ne 1) { throw "REL-011 signing evidence does not contain exactly one $Label asset: $Name" }
    $signedHash = Normalize-Sha256 $matches[0].sha256 "Signed $Label hash"
    if ($signedHash -ne $ExpectedHash) { throw "Signed $Label hash does not match APL-REL-014." }
    $actualPath = Join-Path $releasePath $Name
    if (-not (Test-Path -LiteralPath $actualPath -PathType Leaf)) { throw "Signed $Label asset is missing from release directory: $Name" }
    $actualHash = (Get-FileHash -LiteralPath $actualPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $ExpectedHash) { throw "On-disk $Label hash does not match APL-REL-014." }
}

$rel014FileHash = (Get-FileHash -LiteralPath $rel014Path -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-SignedRel014Asset $rel014Name $rel014FileHash 'APL-REL-014 lifecycle evidence'
Assert-SignedRel014Asset ([string]$rel014.release_assets.setup.filename) $rel014SetupHash 'Setup'
Assert-SignedRel014Asset ([string]$rel014.release_assets.portable_zip.filename) $rel014PortableHash 'portable ZIP'

# Positive check: exact customer download set must pass first. This authenticates
# the manifest/signature that covers the REL-014 evidence and exact product set.
Invoke-ReleaseVerifier -Directory $releasePath -ExpectSuccess $true

# Provenance check: exact clean release commit, exact tag, canonical main ancestry.
Push-Location $repoRoot
try {
    if ((Invoke-Git @('rev-parse', '--is-inside-work-tree')) -ne 'true') {
        throw 'APL-REL-013 must run from the Proxy Launcher Git worktree.'
    }

    $head = (Invoke-Git @('rev-parse', 'HEAD')).ToLowerInvariant()
    if ($head -ne $GitCommit.ToLowerInvariant()) {
        throw "Current HEAD is not the exact release commit. HEAD=$head expected=$($GitCommit.ToLowerInvariant())"
    }

    $tagCommit = (Invoke-Git @('rev-parse', "$GitTag^{commit}")).ToLowerInvariant()
    if ($tagCommit -ne $GitCommit.ToLowerInvariant()) {
        throw "Release tag does not resolve to the release commit. Tag=$tagCommit expected=$($GitCommit.ToLowerInvariant())"
    }

    & git merge-base --is-ancestor $GitCommit main 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Release commit is not an ancestor of canonical local main.' }

    if (Invoke-Git @('status', '--porcelain')) {
        throw 'Git worktree is not clean. Publication gate requires a clean exact-release checkout.'
    }
}
finally {
    Pop-Location
}

# Negative check on a disposable copy. The real final release is never modified.
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('apl-rel-013-' + [Guid]::NewGuid().ToString('N'))
$tempRelease = Join-Path $tempRoot 'release'
New-Item -ItemType Directory -Path $tempRelease -Force | Out-Null
try {
    Copy-Item -Path (Join-Path $releasePath '*') -Destination $tempRelease -Recurse -Force

    $assetNames = @($evidence.assets | ForEach-Object { [string]$_.name })
    $tamperName = $assetNames | Where-Object {
        $_ -ne 'verify_russian_release.ps1' -and $_ -ne 'VERIFY_RUSSIAN_RELEASE.cmd'
    } | Select-Object -First 1
    if (-not $tamperName) { $tamperName = $assetNames | Select-Object -First 1 }
    if (-not $tamperName) { throw 'No signed asset is available for the mandatory negative tamper test.' }

    $tamperPath = Join-Path $tempRelease $tamperName
    if (-not (Test-Path -LiteralPath $tamperPath -PathType Leaf)) {
        throw "Tamper-test asset is missing: $tamperName"
    }
    [System.IO.File]::AppendAllText($tamperPath, "`r`nAPL-REL-013-TAMPER-TEST", [System.Text.Encoding]::UTF8)
    Invoke-ReleaseVerifier -Directory $tempRelease -ExpectSuccess $false
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if (-not $DecisionOutputPath) {
    $DecisionOutputPath = Join-Path (Split-Path -Parent $releasePath) ((Split-Path -Leaf $releasePath) + '.production-release-gate.json')
}
$decisionFullPath = [System.IO.Path]::GetFullPath($DecisionOutputPath)
$releasePrefix = $releasePath.TrimEnd('\') + '\'
if ($decisionFullPath.StartsWith($releasePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Decision output must be outside the signed release directory; otherwise it would invalidate REL-012 verification.'
}

$decision = [ordered]@{
    schema_version = 2
    task = 'APL-REL-013'
    product = 'Arvectum Proxy Launcher'
    version = $Version
    git_tag = $GitTag
    git_commit = $GitCommit.ToLowerInvariant()
    decision = 'PUBLISH'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    release_directory = $releasePath
    signer_thumbprint = $expectedThumbprint
    signer_subject = [string]$evidence.signer_subject
    rel011_detached_signature_verified = $true
    rel012_exact_release_verification = 'PASS'
    rel012_negative_tamper_test = 'PASS_EXPECTED_FAILURE'
    rel014_exact_lifecycle_evidence = 'PASS'
    rel014_signed_asset_binding = 'PASS'
    rel014_candidate_source_commit = ([string]$rel014.candidate_source_commit).ToLowerInvariant()
    rel014_evidence_sha256 = $rel014FileHash
    rel014_setup_sha256 = $rel014SetupHash
    rel014_portable_sha256 = $rel014PortableHash
    rel014_application_sha256 = $rel014AppHash
    git_head_exact = $true
    git_tag_exact = $true
    canonical_main_ancestry = $true
    clean_worktree = $true
    embedded_code_signing_activated = $false
    authenticode_trust_claimed = $false
    smartscreen_trust_claimed = $false
    pin_stored = $false
    private_key_export_attempted = $false
}
$decision | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $decisionFullPath -Encoding UTF8

Write-Host ''
Write-Host 'APL-REL-013 Russian production release gate: PASS'
Write-Host 'Publication decision: PUBLISH'
Write-Host "Version: $Version"
Write-Host "Git tag: $GitTag"
Write-Host "Git commit: $($GitCommit.ToLowerInvariant())"
Write-Host "Signer: $([string]$evidence.signer_subject)"
Write-Host 'REL-012 exact final set verification: PASS'
Write-Host 'APL-REL-014 exact lifecycle evidence signed-set binding: PASS'
Write-Host 'Negative tamper test: PASS (tampered copy correctly rejected)'
Write-Host 'Authenticode/SmartScreen trust claimed: NO'
Write-Host "Decision evidence: $decisionFullPath"
