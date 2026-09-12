<#
.SYNOPSIS
    Adds the APL-REL-012 consumer verification UX to a final release directory.
.DESCRIPTION
    Run this BEFORE tools/russian_signed_release.ps1. The copied verification
    files then become ordinary release assets and are covered by SHA256SUMS.txt
    and the qualified detached signature.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ReleaseDirectory -PathType Container)) {
    throw "Release directory does not exist: $ReleaseDirectory"
}

$releasePath = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$verifierSource = Join-Path $PSScriptRoot 'verify_russian_release.ps1'
$launcherSource = Join-Path $PSScriptRoot 'VERIFY_RUSSIAN_RELEASE.cmd'

foreach ($source in @($verifierSource, $launcherSource)) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required REL-012 source file is missing: $source"
    }
}

# Windows PowerShell 5.1 treats UTF-8 .ps1 files without a BOM as ANSI when
# invoked through -File. The verifier contains Russian end-user text, so package
# the release copy explicitly as UTF-8 with BOM. The repository source remains
# normal UTF-8 and the exact packaged bytes are covered by REL-011 afterwards.
$verifierDestination = Join-Path $releasePath 'verify_russian_release.ps1'
$verifierText = [System.IO.File]::ReadAllText($verifierSource, [System.Text.Encoding]::UTF8)
$utf8Bom = New-Object System.Text.UTF8Encoding -ArgumentList $true
[System.IO.File]::WriteAllText($verifierDestination, $verifierText, $utf8Bom)

$verifierBytes = [System.IO.File]::ReadAllBytes($verifierDestination)
if (
    $verifierBytes.Length -lt 3 -or
    $verifierBytes[0] -ne 0xEF -or
    $verifierBytes[1] -ne 0xBB -or
    $verifierBytes[2] -ne 0xBF
) {
    throw 'Packaged REL-012 verifier is not UTF-8 with BOM.'
}

Copy-Item -LiteralPath $launcherSource -Destination (Join-Path $releasePath 'VERIFY_RUSSIAN_RELEASE.cmd') -Force

Write-Host 'APL-REL-012 verification UX added to release directory.'
Write-Host 'Packaged verifier encoding: UTF-8 with BOM (Windows PowerShell 5.1 safe).'
Write-Host 'Next: run tools/russian_signed_release.ps1 so both verifier files are included in SHA256SUMS.txt.'
