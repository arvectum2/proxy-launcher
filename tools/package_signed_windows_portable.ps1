<#
.SYNOPSIS
    Repackages the canonical Windows portable around an already Authenticode-signed app.
.DESCRIPTION
    APL-REL-016 requires application signing before portable packaging. This helper
    validates the signed application identity, rebuilds the canonical portable package,
    regenerates checksums, applies the existing APL-IP-004 license bundle, updates
    build-result.json and verifies the final archive contains the exact signed bytes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SignedApplication,

    [Parameter(Mandatory = $true)]
    [string]$BuildResultPath,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedPublisher,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedThumbprint,

    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'APL-REL-016 signed portable packaging must run on Windows.'
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root
$CodeSigningEkuOid = '1.3.6.1.5.5.7.3.3'
$RsaOid = '1.2.840.113549.1.1.1'

function Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Normalize-Thumbprint([string]$Value) {
    return ($Value -replace '\s', '').ToUpperInvariant()
}

function Assert-CodeSigningCertificate([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate) {
    if (-not $Certificate) { throw 'Signed application has no signer certificate.' }

    $hasCodeSigningEku = $false
    foreach ($extension in $Certificate.Extensions) {
        if ($extension.Oid.Value -eq '2.5.29.37') {
            $eku = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]$extension
            foreach ($oid in $eku.EnhancedKeyUsages) {
                if ($oid.Value -eq $CodeSigningEkuOid) {
                    $hasCodeSigningEku = $true
                    break
                }
            }
        }
    }
    if (-not $hasCodeSigningEku) { throw "Signer lacks Code Signing EKU $CodeSigningEkuOid." }
    if ($Certificate.PublicKey.Oid.Value -ne $RsaOid) { throw 'Signer public key is not RSA.' }

    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($Certificate)
    if (-not $rsa) { throw 'Unable to resolve RSA public key.' }
    try {
        if ($rsa.KeySize -lt 3072) { throw "RSA key size $($rsa.KeySize) is below the 3072-bit public code-signing minimum." }
    } finally {
        $rsa.Dispose()
    }
}

function Assert-SignedApplication([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status.ToString() -cne 'Valid') {
        throw "Signed application Authenticode status is $($signature.Status), expected Valid."
    }
    Assert-CodeSigningCertificate $signature.SignerCertificate
    if ($signature.SignerCertificate.Subject -cne $ExpectedPublisher) {
        throw "Signed application publisher mismatch: '$($signature.SignerCertificate.Subject)' != '$ExpectedPublisher'."
    }
    $actualThumbprint = Normalize-Thumbprint $signature.SignerCertificate.Thumbprint
    $expected = Normalize-Thumbprint $ExpectedThumbprint
    if ($actualThumbprint -cne $expected) {
        throw "Signed application thumbprint mismatch: '$actualThumbprint' != '$expected'."
    }
    return $signature
}

$application = (Resolve-Path -LiteralPath $SignedApplication).Path
$sourceBuildResultPath = (Resolve-Path -LiteralPath $BuildResultPath).Path
$sourceBuild = Get-Content -LiteralPath $sourceBuildResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
$canonicalVersion = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
$currentCommit = (git rev-parse HEAD).Trim()

if ([string]$sourceBuild.product -cne 'Arvectum Proxy Launcher') { throw 'Source build-result product mismatch.' }
if ([string]$sourceBuild.platform -cne 'windows-x64') { throw 'Source build-result platform mismatch.' }
if ([string]$sourceBuild.format -cne 'portable') { throw 'Source build-result format must be portable.' }
if ([string]$sourceBuild.version -cne $canonicalVersion) { throw 'Source build-result version does not match VERSION.' }
if ([string]$sourceBuild.source_commit -cne $currentCommit) { throw 'Source build-result source_commit does not match HEAD.' }
if ([string]::IsNullOrWhiteSpace([string]$sourceBuild.exe_sha256)) { throw 'Source build-result lacks pre-sign executable SHA-256.' }

$signature = Assert-SignedApplication $application
$signedExeHash = Hash $application
$preSignExeHash = ([string]$sourceBuild.exe_sha256).ToLowerInvariant()
if ($signedExeHash -ceq $preSignExeHash) {
    throw 'Signed application hash is identical to the pre-sign build hash; embedded signing did not change the PE bytes.'
}

$info = (Get-Item -LiteralPath $application).VersionInfo
if ([string]$info.ProductName -cne 'Arvectum Proxy Launcher') { throw 'Signed application ProductName mismatch.' }
if ([string]$info.CompanyName -cne 'ООО «Арвектум»') { throw 'Signed application CompanyName mismatch.' }
if ([string]$info.ProductVersion -cne $canonicalVersion) { throw 'Signed application ProductVersion mismatch.' }

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root 'out\public-signed'
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

$artifactName = "Arvectum-Proxy-Launcher-$canonicalVersion-windows-x64-portable"
$zipName = "$artifactName.zip"
$zipPath = Join-Path $OutputDirectory $zipName
$stageRoot = Join-Path $env:TEMP ("apl-rel-016-portable-" + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $stageRoot $artifactName
New-Item -ItemType Directory -Path $stage -Force | Out-Null

try {
    Copy-Item -LiteralPath $application -Destination (Join-Path $stage 'Arvectum Proxy Launcher.exe')
    Copy-Item -LiteralPath (Join-Path $root 'release\README_WINDOWS_PORTABLE.txt') -Destination (Join-Path $stage 'README.txt')
    Copy-Item -LiteralPath (Join-Path $root 'qa\diagnose_app_control.ps1') -Destination (Join-Path $stage 'diagnose_app_control.ps1')
    Copy-Item -LiteralPath (Join-Path $root 'qa\run_p01_native_qa_v2.ps1') -Destination (Join-Path $stage 'run_p01_native_qa_v2.ps1')
    Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Value "$signedExeHash  Arvectum Proxy Launcher.exe" -Encoding ascii

    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path "$stage\*" -DestinationPath $zipPath -Force

    $signedBuild = [ordered]@{}
    foreach ($property in $sourceBuild.PSObject.Properties) {
        $signedBuild[$property.Name] = $property.Value
    }
    $signedBuild['artifact_name'] = $artifactName
    $signedBuild['zip_file'] = $zipName
    $signedBuild['pre_sign_exe_sha256'] = $preSignExeHash
    $signedBuild['exe_sha256'] = $signedExeHash
    $signedBuild['zip_sha256'] = Hash $zipPath
    $signedBuild['authenticode_signed'] = $true
    $signedBuild['authenticode_publisher'] = $signature.SignerCertificate.Subject
    $signedBuild['authenticode_thumbprint'] = Normalize-Thumbprint $signature.SignerCertificate.Thumbprint
    $signedBuild['authenticode_code_signing_eku'] = $true
    $signedBuild['authenticode_key_algorithm'] = 'RSA'
    $signedBuild['authenticode_packaging_task'] = 'APL-REL-016'
    $signedBuild['packaging_order'] = 'application-signed-before-portable'

    $signedBuildResultPath = Join-Path $OutputDirectory 'build-result.json'
    $signedBuild | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $signedBuildResultPath -Encoding utf8

    & (Join-Path $root 'tools\windows_promoted_license_compliance.ps1') -PortableZip $zipPath
    if ($LASTEXITCODE -ne 0) { throw 'APL-IP-004 promoted portable license compliance failed.' }

    $verifyRoot = Join-Path $stageRoot 'verify'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $verifyRoot -Force
    $insideExe = Join-Path $verifyRoot 'Arvectum Proxy Launcher.exe'
    if (-not (Test-Path -LiteralPath $insideExe -PathType Leaf)) { throw 'Final portable ZIP lacks application executable.' }
    if ((Hash $insideExe) -cne $signedExeHash) { throw 'Final portable ZIP application bytes do not match the approved signed application.' }
    $insideSignature = Assert-SignedApplication $insideExe

    $internalSums = Join-Path $verifyRoot 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $internalSums -PathType Leaf)) { throw 'Final portable ZIP lacks internal SHA256SUMS.txt.' }
    $sumMatch = Select-String -LiteralPath $internalSums -Pattern '^[0-9A-Fa-f]{64}\s+Arvectum Proxy Launcher\.exe$'
    if (@($sumMatch).Count -ne 1) { throw 'Final portable internal checksum manifest is ambiguous.' }
    $manifestHash = ($sumMatch[0].Line -split '\s+')[0].ToLowerInvariant()
    if ($manifestHash -cne $signedExeHash) { throw 'Final portable internal checksum does not cover the signed application bytes.' }

    $finalBuild = Get-Content -LiteralPath $signedBuildResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $finalZipHash = Hash $zipPath
    if ([string]$finalBuild.zip_sha256 -cne $finalZipHash) { throw 'Final build-result ZIP hash does not match APL-IP-004 output.' }
    if ([string]$finalBuild.exe_sha256 -cne $signedExeHash) { throw 'Final build-result executable hash does not match signed application.' }

    Write-Host "APL-REL-016 signed portable PASS: $zipPath"
    Write-Host "Signed application SHA256=$signedExeHash"
    Write-Host "Final portable SHA256=$finalZipHash"
    Write-Host "Publisher=$($insideSignature.SignerCertificate.Subject)"

    if ($env:GITHUB_OUTPUT) {
        "signed_portable_path=$zipPath" >> $env:GITHUB_OUTPUT
        "signed_build_result_path=$signedBuildResultPath" >> $env:GITHUB_OUTPUT
        "signed_application_sha256=$signedExeHash" >> $env:GITHUB_OUTPUT
        "signed_portable_sha256=$finalZipHash" >> $env:GITHUB_OUTPUT
    }
} finally {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
}
