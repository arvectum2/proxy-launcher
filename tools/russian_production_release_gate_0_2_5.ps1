<#
.SYNOPSIS
    Fail-closed Russian production publication gate for the exact 0.2.5 CFA hotfix set.
.DESCRIPTION
    Validates REL-011 signed evidence, REL-012 consumer verification, the exact
    APL-REL-015 CFA/reboot acceptance binding, a negative tamper test, and exact
    Git provenance. It never signs, stores a PIN, or exports a private key.
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
    throw 'APL-REL-013/015 production release gate must run on Windows against the exact final Russian release set.'
}
if ($Version -cne '0.2.5') {
    throw "This exact hotfix gate is only valid for Version=0.2.5; received $Version"
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
        if ($exitCode -ne 0 -or $text -notmatch '(?m)^APL_REL_012_RESULT=PASS\s*$') {
            throw "REL-012 verification did not PASS for the exact final release set. Exit=$exitCode"
        }
    }
    else {
        if ($exitCode -eq 0 -or $text -notmatch '(?m)^APL_REL_012_RESULT=FAIL\s*$') {
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

$rel015Name = 'apl-rel-015-cfa-hotfix-evidence.json'
$required = @(
    'SHA256SUMS.txt',
    'SHA256SUMS.txt.sig',
    'signer-certificate.cer',
    'signing-evidence.json',
    'verify_russian_release.ps1',
    'VERIFY_RUSSIAN_RELEASE.cmd',
    $rel015Name
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
    throw "Signer thumbprint is not the governed Arvectum release-evidence identity: $evidenceThumbprint"
}
$arvectumName = -join ([char[]](0x0410,0x0420,0x0412,0x0415,0x041A,0x0422,0x0423,0x041C))
if (([string]$evidence.signer_subject) -notmatch [regex]::Escape($arvectumName)) {
    throw 'Signing evidence subject does not identify the governed Arvectum organization.'
}

$rel015Path = Join-Path $releasePath $rel015Name
$rel015 = Get-Content -LiteralPath $rel015Path -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$rel015.schema -ne 'arvectum.proxy.apl-rel-015-cfa-hotfix-evidence.v1') { throw 'Unexpected APL-REL-015 evidence schema.' }
if ([string]$rel015.task -ne 'APL-REL-015') { throw 'Hotfix evidence was not produced by APL-REL-015.' }
if ([string]$rel015.product -ne 'Arvectum Proxy Launcher') { throw 'Unexpected product in APL-REL-015 evidence.' }
if ([string]$rel015.result -ne 'PASS') { throw 'APL-REL-015 hotfix evidence is not PASS.' }
if ([string]$rel015.scope -ne 'EXACT_0_2_5_CFA_HOTFIX_SET_READY_FOR_REL011_SIGNING') { throw 'APL-REL-015 evidence scope is unexpected.' }
if ([string]$rel015.version -ne $Version) { throw 'APL-REL-015 version does not match the release version.' }
if ([string]$rel015.signed_set_binding.state -ne 'READY_FOR_REL011_SIGNING') { throw 'APL-REL-015 evidence was not finalized before REL-011 signing.' }
if (-not [bool]$rel015.signed_set_binding.rel013_post_sign_binding_required) { throw 'APL-REL-015 evidence does not require REL-013 post-sign binding.' }
if ([bool]$rel015.signed_set_binding.final_signed_set_pass_claimed) { throw 'APL-REL-015 pre-sign evidence improperly claims final signed-set PASS.' }
if ([string]$rel015.signed_set_binding.required_signing_mode -ne [string]$evidence.signing_mode) { throw 'APL-REL-015 signing mode does not match REL-011 evidence.' }
if ((Normalize-Thumbprint ([string]$rel015.signed_set_binding.required_signer_thumbprint)) -ne $expectedThumbprint) { throw 'APL-REL-015 requires a different signer identity.' }

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$rel015ContractPath = Join-Path $repoRoot 'release\APL_REL_015_0_2_5_CFA_HOTFIX_CONTRACT.json'
if (-not (Test-Path -LiteralPath $rel015ContractPath -PathType Leaf)) { throw 'Repository APL-REL-015 exact hotfix contract is missing.' }
$rel015Contract = Get-Content -LiteralPath $rel015ContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$rel015Contract.schema -ne 'arvectum.proxy.apl-rel-015-cfa-hotfix-contract.v1') { throw 'Repository APL-REL-015 contract schema is unexpected.' }
if ([string]$rel015Contract.version -ne $Version) { throw 'Repository APL-REL-015 contract targets another version.' }
$contractHash = (Get-FileHash -LiteralPath $rel015ContractPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ((Normalize-Sha256 $rel015.source_evidence.contract_sha256 'APL-REL-015 contract hash') -ne $contractHash) { throw 'APL-REL-015 evidence was produced from a different exact hotfix contract.' }
if (([string]$rel015.accepted_product_source_commit).ToLowerInvariant() -ne ([string]$rel015Contract.accepted_product_source_commit).ToLowerInvariant()) { throw 'APL-REL-015 accepted product source drifted from the repository contract.' }

$contractSetupHash = Normalize-Sha256 $rel015Contract.accepted_installer_candidate.setup_sha256 'Contract Setup hash'
$contractAppHash = Normalize-Sha256 $rel015Contract.accepted_installer_candidate.application_sha256 'Contract application hash'
$rel015SetupHash = Normalize-Sha256 $rel015.release_assets.setup.sha256 'APL-REL-015 Setup hash'
$rel015PortableHash = Normalize-Sha256 $rel015.release_assets.portable_zip.sha256 'APL-REL-015 portable hash'
$rel015AppHash = Normalize-Sha256 $rel015.release_assets.accepted_application.sha256 'APL-REL-015 application hash'
if ($rel015SetupHash -ne $contractSetupHash) { throw 'APL-REL-015 Setup hash drifted from the exact hotfix contract.' }
if ($rel015AppHash -ne $contractAppHash) { throw 'APL-REL-015 application hash drifted from the exact hotfix contract.' }
if ((Normalize-Sha256 $rel015.release_assets.portable_zip.application_sha256 'APL-REL-015 portable application hash') -ne $contractAppHash) { throw 'APL-REL-015 portable does not contain the accepted application identity.' }
if ([string]$rel015.release_assets.portable_zip.materialization_policy -ne [string]$rel015Contract.portable_materialization.policy) { throw 'APL-REL-015 portable materialization policy drifted from the contract.' }

foreach ($name in @('issue_171','fresh_install','upgrade','repair','uninstall')) {
    if ([string]$rel015.ci_acceptance.$name -ne 'PASS') { throw "APL-REL-015 CI acceptance gate is not PASS: $name" }
}
if (-not [bool]$rel015.ci_acceptance.configuration_preserved) { throw 'APL-REL-015 CI acceptance did not preserve configuration.' }
if (-not [bool]$rel015.ci_acceptance.foreign_startup_preserved) { throw 'APL-REL-015 CI acceptance did not preserve foreign startup state.' }
if ((Normalize-Sha256 $rel015.ci_acceptance.setup_sha256 'APL-REL-015 CI Setup hash') -ne $contractSetupHash) { throw 'APL-REL-015 CI Setup identity drifted.' }
if ((Normalize-Sha256 $rel015.ci_acceptance.application_sha256 'APL-REL-015 CI application hash') -ne $contractAppHash) { throw 'APL-REL-015 CI application identity drifted.' }

if ([string]$rel015.physical_acceptance.result -ne 'PASS') { throw 'APL-REL-015 physical acceptance is not PASS.' }
if ((Normalize-Sha256 $rel015.physical_acceptance.raw_sha256 'APL-REL-015 raw physical evidence hash') -ne (Normalize-Sha256 $rel015Contract.physical_acceptance.sha256 'Contract raw physical evidence hash')) { throw 'APL-REL-015 raw physical evidence identity drifted.' }
if ((Normalize-Sha256 $rel015.physical_acceptance.application_sha256 'APL-REL-015 physical application hash') -ne $contractAppHash) { throw 'APL-REL-015 physical application identity drifted.' }
if ([string]$rel015.physical_acceptance.pac_url -ne [string]$rel015Contract.physical_acceptance.required_pac_url) { throw 'APL-REL-015 physical PAC URL drifted.' }
if ([int]$rel015.physical_acceptance.pac_http_status -ne 200) { throw 'APL-REL-015 physical PAC HTTP status is not 200.' }
if ([int]$rel015.physical_acceptance.https_status -ne 200) { throw 'APL-REL-015 physical HTTPS-through-proxy status is not 200.' }
foreach ($checkName in @($rel015Contract.physical_acceptance.required_checks)) {
    if (-not [bool]$rel015.physical_acceptance.checks.$checkName) { throw "APL-REL-015 physical check is not PASS: $checkName" }
}

if ([string]$rel015.inherited_runtime_trust_baseline.status -ne 'PASS') { throw 'APL-REL-015 inherited runtime/toolchain regression baseline is not PASS.' }
if ([string]$rel015.inherited_runtime_trust_baseline.build_python_version -ne [string]$rel015Contract.inherited_runtime_trust_baseline.build_python_version) { throw 'APL-REL-015 build Python baseline drifted.' }
if ([string]$rel015.inherited_runtime_trust_baseline.pyinstaller_version -ne [string]$rel015Contract.inherited_runtime_trust_baseline.pyinstaller_version) { throw 'APL-REL-015 PyInstaller baseline drifted.' }

$signedAssets = @($evidence.assets)
function Assert-SignedRel015Asset([string]$Name, [string]$ExpectedHash, [string]$Label) {
    $matches = @($signedAssets | Where-Object { ([string]$_.name) -ceq $Name })
    if ($matches.Count -ne 1) { throw "REL-011 signing evidence does not contain exactly one $Label asset: $Name" }
    $signedHash = Normalize-Sha256 $matches[0].sha256 "Signed $Label hash"
    if ($signedHash -ne $ExpectedHash) { throw "Signed $Label hash does not match APL-REL-015." }
    $actualPath = Join-Path $releasePath $Name
    if (-not (Test-Path -LiteralPath $actualPath -PathType Leaf)) { throw "Signed $Label asset is missing from release directory: $Name" }
    $actualHash = (Get-FileHash -LiteralPath $actualPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $ExpectedHash) { throw "On-disk $Label hash does not match APL-REL-015." }
}

$rel015FileHash = (Get-FileHash -LiteralPath $rel015Path -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-SignedRel015Asset $rel015Name $rel015FileHash 'APL-REL-015 hotfix evidence'
Assert-SignedRel015Asset ([string]$rel015.release_assets.setup.filename) $rel015SetupHash 'Setup'
Assert-SignedRel015Asset ([string]$rel015.release_assets.portable_zip.filename) $rel015PortableHash 'portable ZIP'

Invoke-ReleaseVerifier -Directory $releasePath -ExpectSuccess $true

Push-Location $repoRoot
try {
    if ((Invoke-Git @('rev-parse', '--is-inside-work-tree')) -ne 'true') {
        throw 'APL-REL-013/015 must run from the Proxy Launcher Git worktree.'
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('apl-rel-013-015-' + [Guid]::NewGuid().ToString('N'))
$tempRelease = Join-Path $tempRoot 'release'
New-Item -ItemType Directory -Path $tempRelease -Force | Out-Null
try {
    Copy-Item -Path (Join-Path $releasePath '*') -Destination $tempRelease -Recurse -Force

    $tamperName = [string]$rel015.release_assets.portable_zip.filename
    if (-not $tamperName) { $tamperName = $rel015Name }
    $tamperPath = Join-Path $tempRelease $tamperName
    if (-not (Test-Path -LiteralPath $tamperPath -PathType Leaf)) {
        throw "Tamper-test asset is missing: $tamperName"
    }
    [System.IO.File]::AppendAllText($tamperPath, "`r`nAPL-REL-013-015-TAMPER-TEST", [System.Text.Encoding]::UTF8)
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
    schema_version = 3
    task = 'APL-REL-013'
    release_profile = 'APL-REL-015-0.2.5-CFA-HOTFIX'
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
    rel015_exact_hotfix_evidence = 'PASS'
    rel015_signed_asset_binding = 'PASS'
    rel015_accepted_product_source_commit = ([string]$rel015.accepted_product_source_commit).ToLowerInvariant()
    rel015_evidence_sha256 = $rel015FileHash
    rel015_setup_sha256 = $rel015SetupHash
    rel015_portable_sha256 = $rel015PortableHash
    rel015_application_sha256 = $rel015AppHash
    rel015_physical_evidence_sha256 = ([string]$rel015.physical_acceptance.raw_sha256).ToLowerInvariant()
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
$decision | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $decisionFullPath -Encoding UTF8

Write-Host ''
Write-Host 'APL-REL-013/015 Russian production release gate: PASS'
Write-Host 'Publication decision: PUBLISH'
Write-Host "Version: $Version"
Write-Host "Git tag: $GitTag"
Write-Host "Git commit: $($GitCommit.ToLowerInvariant())"
Write-Host "Signer: $([string]$evidence.signer_subject)"
Write-Host 'REL-012 exact final set verification: PASS'
Write-Host 'APL-REL-015 exact CFA hotfix evidence signed-set binding: PASS'
Write-Host 'Negative tamper test: PASS (tampered copy correctly rejected)'
Write-Host 'Authenticode/SmartScreen trust claimed: NO'
Write-Host "Decision evidence: $decisionFullPath"
