[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DriverPackageDirectory,
    [Parameter(Mandatory=$true)][string]$ServicePath,
    [Parameter(Mandatory=$true)][string]$DriverPackageToolPath,
    [ValidateSet('Test','Production')][string]$SigningMode,
    [string]$ExpectedServicePublisher,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\out\windows-native-stack')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows native-stack bundle must be built on Windows.' }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function SigEvidence([string]$Path) {
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    [ordered]@{
        status = $sig.Status.ToString()
        subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { $null }
        thumbprint = if ($sig.SignerCertificate) { $sig.SignerCertificate.Thumbprint } else { $null }
    }
}

$package = (Resolve-Path -LiteralPath $DriverPackageDirectory).Path
$service = (Resolve-Path -LiteralPath $ServicePath).Path
$tool = (Resolve-Path -LiteralPath $DriverPackageToolPath).Path
$inf = Join-Path $package 'ArvectumProxyRoutingCallout.inf'
$cat = Join-Path $package 'ArvectumProxyRoutingCallout.cat'
$sys = Join-Path $package 'ArvectumProxyRoutingCallout.sys'
foreach ($required in @($inf,$cat,$sys)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Driver package is incomplete: $required"
    }
}
$catalogSig = SigEvidence $cat
$serviceSig = SigEvidence $service
$toolSig = SigEvidence $tool

if ($SigningMode -eq 'Production') {
    if ($catalogSig.status -cne 'Valid') { throw "Production catalog Authenticode status is $($catalogSig.status), expected Valid." }
    if ([string]::IsNullOrWhiteSpace([string]$catalogSig.subject) -or [string]$catalogSig.subject -notmatch 'Microsoft Windows Hardware Compatibility Publisher') {
        throw 'Production driver catalog is not signed by Microsoft Windows Hardware Compatibility Publisher.'
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedServicePublisher)) {
        throw 'Production bundle requires -ExpectedServicePublisher.'
    }
    foreach ($item in @(
        [pscustomobject]@{ role='routing service'; sig=$serviceSig },
        [pscustomobject]@{ role='driver package tool'; sig=$toolSig }
    )) {
        if ($item.sig.status -cne 'Valid') { throw "Production $($item.role) Authenticode status is $($item.sig.status), expected Valid." }
        if ([string]$item.sig.subject -cne $ExpectedServicePublisher) { throw "Production $($item.role) publisher mismatch." }
    }
}

Remove-Item -LiteralPath $OutputDirectory -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
foreach ($name in @('ArvectumProxyRoutingCallout.inf','ArvectumProxyRoutingCallout.cat','ArvectumProxyRoutingCallout.sys')) {
    Copy-Item -LiteralPath (Join-Path $package $name) -Destination (Join-Path $OutputDirectory $name)
}
$serviceOut = Join-Path $OutputDirectory 'ArvectumProxyRoutingService.exe'
$toolOut = Join-Path $OutputDirectory 'ArvectumDriverPackageTool.exe'
Copy-Item -LiteralPath $service -Destination $serviceOut
Copy-Item -LiteralPath $tool -Destination $toolOut

$manifest = [ordered]@{
    schema = 'arvectum.proxy.windows-native-stack.v1'
    signing_mode = $SigningMode.ToLowerInvariant()
    protocol_version = 3
    generated_utc = [DateTime]::UtcNow.ToString('o')
    source_commit = (git rev-parse HEAD).Trim()
    version = (Get-Content VERSION -Raw).Trim()
    driver = [ordered]@{
        filename = 'ArvectumProxyRoutingCallout.sys'
        service_name = 'ArvectumProxyRoutingCallout'
        sha256 = Hash (Join-Path $OutputDirectory 'ArvectumProxyRoutingCallout.sys')
        package = [ordered]@{
            directory = '.'
            inf_filename = 'ArvectumProxyRoutingCallout.inf'
            inf_sha256 = Hash (Join-Path $OutputDirectory 'ArvectumProxyRoutingCallout.inf')
            catalog_filename = 'ArvectumProxyRoutingCallout.cat'
            catalog_sha256 = Hash (Join-Path $OutputDirectory 'ArvectumProxyRoutingCallout.cat')
            catalog_signature = $catalogSig
        }
    }
    service = [ordered]@{
        filename = 'ArvectumProxyRoutingService.exe'
        service_name = 'ArvectumProxyRouting'
        sha256 = Hash $serviceOut
        signature = $serviceSig
    }
    package_tool = [ordered]@{
        filename = 'ArvectumDriverPackageTool.exe'
        sha256 = Hash $toolOut
        signature = $toolSig
    }
}
$manifestPath = Join-Path $OutputDirectory 'native-stack-bundle.json'
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output "ARVECTUM_WINDOWS_NATIVE_STACK_BUNDLE_READY mode=$SigningMode path=$OutputDirectory"
