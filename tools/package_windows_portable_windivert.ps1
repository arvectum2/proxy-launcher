[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PortableZip,
    [Parameter(Mandatory = $true)]
    [string]$BuildResultPath,
    [Parameter(Mandatory = $true)]
    [string]$WinDivertStackBundle
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root

function Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$zip = (Resolve-Path -LiteralPath $PortableZip).Path
$buildResultPath = (Resolve-Path -LiteralPath $BuildResultPath).Path
$bundle = (Resolve-Path -LiteralPath $WinDivertStackBundle).Path
$helper = Join-Path $root 'installer\windivert_service_helper.ps1'
$canonicalVersion = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
$head = (git rev-parse HEAD).Trim().ToLowerInvariant()

$build = Get-Content -LiteralPath $buildResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$build.product -cne 'Arvectum Proxy Launcher') { throw 'Portable build-result product mismatch.' }
if ([string]$build.platform -cne 'windows-x64') { throw 'Portable build-result platform mismatch.' }
if ([string]$build.format -cne 'portable') { throw 'Portable build-result format mismatch.' }
if ([string]$build.version -cne $canonicalVersion) { throw 'Portable build-result version mismatch.' }
if ([string]$build.source_commit -cne $head) { throw 'Portable build-result source_commit does not match HEAD.' }
if ([string]$build.exe_sha256 -notmatch '^[0-9a-f]{64}$') { throw 'Portable build-result EXE hash is invalid.' }

$stackManifestPath = Join-Path $bundle 'windivert-stack-build.json'
$dependencyManifestPath = Join-Path $bundle 'windivert-dependency.json'
foreach ($required in @(
    $helper,
    $stackManifestPath,
    $dependencyManifestPath,
    (Join-Path $bundle 'ArvectumProxyWinDivertRoutingService.exe'),
    (Join-Path $bundle 'WinDivert.dll'),
    (Join-Path $bundle 'WinDivert64.sys'),
    (Join-Path $bundle 'WinDivert-LICENSE')
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Portable WinDivert payload is incomplete: $required"
    }
}

$stack = Get-Content -LiteralPath $stackManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$dependency = Get-Content -LiteralPath $dependencyManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$stack.schema -cne 'arvectum.proxy.windows-windivert-build.v1') { throw 'Unexpected WinDivert stack manifest schema.' }
if ([string]$stack.source_commit -cne $head) { throw 'WinDivert stack source_commit does not match HEAD.' }
if ([string]$stack.version -cne '2.2.2') { throw 'Unexpected WinDivert stack version.' }
if ([string]$dependency.schema -cne 'arvectum.proxy.windivert-dependency.v1') { throw 'Unexpected WinDivert dependency schema.' }
if ([string]$dependency.version -cne '2.2.2') { throw 'Unexpected WinDivert dependency version.' }

$expectedDriverHash = '8da085332782708d8767bcace5327a6ec7283c17cfb85e40b03cd2323a90ddc2'
$expectedDllHash = 'c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2'
$expectedLicenseHash = '14a0cb5214d536e4fdae6aa3f5696f981eeda106cd026e9794bba489ee79d628'
$expectedSigner = '043589F75FCE2795E7F2CC3E526D46784D5DDAB3'
$driver = Join-Path $bundle 'WinDivert64.sys'
$dll = Join-Path $bundle 'WinDivert.dll'
$license = Join-Path $bundle 'WinDivert-LICENSE'
$service = Join-Path $bundle 'ArvectumProxyWinDivertRoutingService.exe'

if ((Hash $driver) -cne $expectedDriverHash) { throw 'Portable WinDivert driver hash mismatch.' }
if ((Hash $dll) -cne $expectedDllHash) { throw 'Portable WinDivert DLL hash mismatch.' }
if ((Hash $license) -cne $expectedLicenseHash) { throw 'Portable WinDivert license hash mismatch.' }
if ((Hash $service) -cne ([string]$stack.service.sha256).ToLowerInvariant()) { throw 'Portable WinDivert service hash mismatch.' }
if ((Hash $dependencyManifestPath) -cne ([string]$stack.dependency_manifest_sha256).ToLowerInvariant()) { throw 'Portable WinDivert dependency manifest hash mismatch.' }

$signature = Get-AuthenticodeSignature -LiteralPath $driver
if ($signature.Status.ToString() -cne 'Valid') { throw 'Portable WinDivert driver Authenticode status is not Valid.' }
if (-not $signature.SignerCertificate) { throw 'Portable WinDivert driver signer certificate is absent.' }
if (($signature.SignerCertificate.Thumbprint -replace '\s','').ToUpperInvariant() -cne $expectedSigner) {
    throw 'Portable WinDivert driver signer thumbprint is not pinned.'
}

$work = Join-Path $env:TEMP ("apl-portable-windivert-" + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $work 'stage'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
    Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
    $exe = Join-Path $stage 'Arvectum Proxy Launcher.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Portable ZIP lacks application executable.' }
    if ((Hash $exe) -cne ([string]$build.exe_sha256).ToLowerInvariant()) { throw 'Portable ZIP application hash does not match build-result.' }

    $portableBundle = Join-Path $stage 'WINDOWS_WINDIVERT'
    New-Item -ItemType Directory -Path $portableBundle -Force | Out-Null
    foreach ($name in @(
        'ArvectumProxyWinDivertRoutingService.exe',
        'WinDivert.dll',
        'WinDivert64.sys',
        'WinDivert-LICENSE',
        'windivert-dependency.json',
        'windivert-stack-build.json'
    )) {
        Copy-Item -LiteralPath (Join-Path $bundle $name) -Destination (Join-Path $portableBundle $name) -Force
    }
    Copy-Item -LiteralPath $helper -Destination (Join-Path $portableBundle 'windivert_service_helper.ps1') -Force

    $portableManifest = [ordered]@{
        product = 'Arvectum Proxy Launcher'
        version = $canonicalVersion
        canonical_version = $canonicalVersion
        platform = 'windows-x64'
        format = 'portable'
        source_commit = $head
        application_sha256 = (Hash $exe)
        windivert_stack_enabled = $true
        windivert_dependency_manifest_sha256 = (Hash $dependencyManifestPath)
        windivert_stack_manifest_sha256 = (Hash $stackManifestPath)
        windivert_service_helper_sha256 = (Hash $helper)
        windivert_service_sha256 = (Hash $service)
    }
    $portableManifestPath = Join-Path $stage 'build_manifest.json'
    $portableManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $portableManifestPath -Encoding utf8

    $outDir = Split-Path -Parent $zip
    $candidateZip = Join-Path $outDir (
        ([IO.Path]::GetFileNameWithoutExtension($zip)) +
        ".windivert-" + [guid]::NewGuid().ToString('N') + ".zip"
    )
    $backupZip = $zip + ".windivert-backup"
    Remove-Item -LiteralPath $candidateZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backupZip -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path "$stage\*" -DestinationPath $candidateZip -Force

    $verify = Join-Path $work 'verify'
    Expand-Archive -LiteralPath $candidateZip -DestinationPath $verify -Force
    foreach ($required in @(
        'build_manifest.json',
        'WINDOWS_WINDIVERT\ArvectumProxyWinDivertRoutingService.exe',
        'WINDOWS_WINDIVERT\WinDivert.dll',
        'WINDOWS_WINDIVERT\WinDivert64.sys',
        'WINDOWS_WINDIVERT\WinDivert-LICENSE',
        'WINDOWS_WINDIVERT\windivert-dependency.json',
        'WINDOWS_WINDIVERT\windivert-stack-build.json',
        'WINDOWS_WINDIVERT\windivert_service_helper.ps1'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $verify $required) -PathType Leaf)) {
            throw "Final portable ZIP lacks WinDivert bootstrap file: $required"
        }
    }
    $verifyManifest = Get-Content -LiteralPath (Join-Path $verify 'build_manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$verifyManifest.source_commit -cne $head -or -not [bool]$verifyManifest.windivert_stack_enabled) {
        throw 'Final portable build manifest is not bound to the production WinDivert stack.'
    }

    [IO.File]::Replace($candidateZip, $zip, $backupZip, $true)
    if (Test-Path -LiteralPath $backupZip) {
        Remove-Item -LiteralPath $backupZip -Force
    }
    $zipHash = Hash $zip
    $build | Add-Member -NotePropertyName windivert_stack_enabled -NotePropertyValue $true -Force
    $build | Add-Member -NotePropertyName windivert_dependency_manifest_sha256 -NotePropertyValue (Hash $dependencyManifestPath) -Force
    $build | Add-Member -NotePropertyName windivert_stack_manifest_sha256 -NotePropertyValue (Hash $stackManifestPath) -Force
    $build | Add-Member -NotePropertyName windivert_service_helper_sha256 -NotePropertyValue (Hash $helper) -Force
    $build | Add-Member -NotePropertyName windivert_service_sha256 -NotePropertyValue (Hash $service) -Force
    $build | Add-Member -NotePropertyName portable_build_manifest_sha256 -NotePropertyValue (Hash (Join-Path $verify 'build_manifest.json')) -Force
    $build.zip_sha256 = $zipHash
    $build | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $buildResultPath -Encoding utf8

    Set-Content -LiteralPath (Join-Path $outDir 'SHA256SUMS.txt') -Value "$zipHash  $(Split-Path $zip -Leaf)" -Encoding ascii
    Write-Host "Portable WinDivert bootstrap PASS: $zip SHA256=$zipHash"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
