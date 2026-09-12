<#
.SYNOPSIS
    Materialize the 0.2.5 customer portable ZIP around the exact application
    bytes that passed physical CFA/reboot acceptance.
.DESCRIPTION
    This is a packaging operation, not a rebuild. It refuses any application
    whose SHA-256 differs from the physically accepted 0.2.5 application and
    uses a pinned same-source portable template only for non-executable package
    material (README, diagnostics and third-party notices/licenses).

    The template executable is explicitly rejected as the release application.
    SHA256SUMS.txt is regenerated for the accepted application before creating
    the final customer ZIP. The resulting ZIP hash is intentionally determined
    at materialization time and is subsequently bound by APL-REL-015 and the
    REL-011 qualified signed manifest.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$AcceptedApplication,
    [Parameter(Mandatory = $true)] [string]$TemplatePortableZip,
    [Parameter(Mandatory = $true)] [string]$OutputPath,
    [string]$ContractPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw '0.2.5 accepted portable materialization must run on Windows.'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $ContractPath) {
    $ContractPath = Join-Path $repoRoot 'release\APL_REL_015_0_2_5_CFA_HOTFIX_CONTRACT.json'
}
if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
    throw "APL-REL-015 contract is missing: $ContractPath"
}
$contract = Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$contract.schema -ne 'arvectum.proxy.apl-rel-015-cfa-hotfix-contract.v1') {
    throw 'Unexpected APL-REL-015 contract schema.'
}
if ([string]$contract.version -ne '0.2.5') {
    throw 'APL-REL-015 contract does not target 0.2.5.'
}

function Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Require-Hash([string]$Path, [string]$Expected, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing: $Path"
    }
    $actual = Hash $Path
    if ($actual -cne ([string]$Expected).ToLowerInvariant()) {
        throw "$Label SHA-256 mismatch: $actual != $Expected"
    }
    Write-Host "PASS hash: $Label = $actual"
}

$acceptedApp = (Resolve-Path -LiteralPath $AcceptedApplication).Path
$templateZip = (Resolve-Path -LiteralPath $TemplatePortableZip).Path
$outputFull = [IO.Path]::GetFullPath($OutputPath)
$outputDir = Split-Path -Parent $outputFull
if (-not $outputDir) { $outputDir = (Get-Location).Path }
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$expectedAppHash = ([string]$contract.portable_materialization.required_application_sha256).ToLowerInvariant()
Require-Hash $acceptedApp $expectedAppHash 'physically accepted application'

$appInfo = (Get-Item -LiteralPath $acceptedApp).VersionInfo
if ([string]$appInfo.ProductVersion -cne '0.2.5') {
    throw "Accepted application ProductVersion mismatch: $($appInfo.ProductVersion)"
}
if ([string]$appInfo.ProductName -cne 'Arvectum Proxy Launcher') {
    throw "Accepted application ProductName mismatch: $($appInfo.ProductName)"
}

Require-Hash $templateZip ([string]$contract.portable_materialization.template_source.inner_portable_zip_sha256) 'portable template ZIP'

$tempRoot = Join-Path $env:TEMP ('apl-0.2.5-portable-materialize-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $tempRoot 'stage'
$verify = Join-Path $tempRoot 'verify'
try {
    New-Item -ItemType Directory -Path $stage,$verify -Force | Out-Null
    Expand-Archive -LiteralPath $templateZip -DestinationPath $stage -Force

    $templateApp = Join-Path $stage 'Arvectum Proxy Launcher.exe'
    Require-Hash $templateApp ([string]$contract.portable_materialization.template_source.template_application_sha256) 'template application (provenance only)'

    $requiredStatic = $contract.portable_materialization.required_static_members
    $staticNames = @($requiredStatic.PSObject.Properties.Name)
    foreach ($name in $staticNames) {
        $relative = $name -replace '/', '\'
        $path = Join-Path $stage $relative
        $expected = [string]$requiredStatic.$name
        Require-Hash $path $expected "template static member $name"
    }

    $expectedMembers = @('Arvectum Proxy Launcher.exe','SHA256SUMS.txt') + $staticNames
    $actualMembers = @(
        Get-ChildItem -LiteralPath $stage -File -Recurse | ForEach-Object {
            $_.FullName.Substring($stage.Length + 1).Replace('\','/')
        }
    )
    foreach ($member in $actualMembers) {
        if ($expectedMembers -cnotcontains $member) {
            throw "Portable template contains unexpected member: $member"
        }
    }
    foreach ($member in $expectedMembers) {
        if ($actualMembers -cnotcontains $member) {
            throw "Portable template is missing required member: $member"
        }
    }

    Copy-Item -LiteralPath $acceptedApp -Destination $templateApp -Force
    Require-Hash $templateApp $expectedAppHash 'staged accepted application'

    $internalManifest = Join-Path $stage 'SHA256SUMS.txt'
    [IO.File]::WriteAllText(
        $internalManifest,
        "$expectedAppHash  Arvectum Proxy Launcher.exe`r`n",
        [Text.Encoding]::ASCII
    )

    if (Test-Path -LiteralPath $outputFull) {
        throw "Output already exists; refusing to overwrite release material: $outputFull"
    }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $outputFull -CompressionLevel Optimal

    Expand-Archive -LiteralPath $outputFull -DestinationPath $verify -Force
    Require-Hash (Join-Path $verify 'Arvectum Proxy Launcher.exe') $expectedAppHash 'final portable application'

    $manifestLine = (Get-Content -LiteralPath (Join-Path $verify 'SHA256SUMS.txt') -Raw -Encoding ASCII).Trim()
    $expectedLine = "$expectedAppHash  Arvectum Proxy Launcher.exe"
    if ($manifestLine -cne $expectedLine) {
        throw "Final portable internal SHA256SUMS mismatch: '$manifestLine'"
    }

    foreach ($name in $staticNames) {
        $relative = $name -replace '/', '\'
        Require-Hash (Join-Path $verify $relative) ([string]$requiredStatic.$name) "final static member $name"
    }

    $finalMembers = @(
        Get-ChildItem -LiteralPath $verify -File -Recurse | ForEach-Object {
            $_.FullName.Substring($verify.Length + 1).Replace('\','/')
        }
    )
    if (@($finalMembers).Count -ne @($expectedMembers).Count) {
        throw 'Final portable ZIP member count differs from governed template.'
    }
    foreach ($member in $expectedMembers) {
        if ($finalMembers -cnotcontains $member) {
            throw "Final portable ZIP is missing governed member: $member"
        }
    }

    $portableHash = Hash $outputFull
    Write-Host ''
    Write-Host 'APL-REL-015 accepted portable materialization: PASS' -ForegroundColor Green
    Write-Host "Application SHA-256: $expectedAppHash"
    Write-Host "Portable ZIP SHA-256: $portableHash"
    Write-Host "Portable ZIP: $outputFull"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
