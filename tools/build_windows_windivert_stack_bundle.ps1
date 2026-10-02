[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\out\windows-windivert-stack'),
    [string]$StageDirectory = (Join-Path $PSScriptRoot '..\out\windows-windivert-stage')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Windows WinDivert stack bundle must be built on Windows.'
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root

function Full-Path([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $root $Path))
}

function Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$out = Full-Path $OutputDirectory
$stage = Full-Path $StageDirectory
if ($out -ieq $stage) {
    throw 'OutputDirectory and StageDirectory must be different.'
}

Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $out -Force | Out-Null

& (Join-Path $root 'tools\stage_windows_windivert.ps1') -OutputDirectory $stage

$programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
$vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw 'vswhere.exe was not found.'
}
$vsInstall = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace([string]$vsInstall)) {
    throw 'Visual C++ x64 build tools were not found.'
}
$vcvars = Join-Path ([string]$vsInstall).Trim() 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path -LiteralPath $vcvars -PathType Leaf)) {
    throw 'vcvars64.bat was not found.'
}

$sdk = Join-Path $stage 'sdk'
$windivertLib = Join-Path $sdk 'WinDivert.lib'
foreach ($required in @(
    (Join-Path $stage 'WinDivert.dll'),
    (Join-Path $stage 'WinDivert64.sys'),
    (Join-Path $stage 'WinDivert-LICENSE'),
    (Join-Path $stage 'windivert-dependency.json'),
    $windivertLib
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Staged WinDivert dependency is incomplete: $required"
    }
}

$serviceOut = Join-Path $out 'ArvectumProxyWinDivertRoutingService.exe'
$sources = @(
    (Join-Path $root 'native\windows_windivert\windivert_service_main.cpp'),
    (Join-Path $root 'native\windows_windivert\windivert_service_protocol.cpp'),
    (Join-Path $root 'native\windows_windivert\windivert_routing_session.cpp')
)
foreach ($source in $sources) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "WinDivert routing service source is missing: $source"
    }
}

$compile = @(
    'call "' + $vcvars + '" >nul &&',
    'cl /nologo /W4 /WX /EHsc /std:c++17 /MT /O2',
    '/I"' + $sdk + '"',
    '"' + $sources[0] + '"',
    '"' + $sources[1] + '"',
    '"' + $sources[2] + '"',
    '"' + $windivertLib + '"',
    '/Fe:"' + $serviceOut + '"',
    '/link Advapi32.lib Bcrypt.lib Ws2_32.lib'
) -join ' '

$cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
if (-not (Test-Path -LiteralPath $cmdExe -PathType Leaf)) {
    throw 'cmd.exe was not found.'
}
& $cmdExe /d /s /c $compile
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $serviceOut -PathType Leaf)) {
    throw 'WinDivert routing service compilation failed.'
}

foreach ($name in @(
    'WinDivert.dll',
    'WinDivert64.sys',
    'WinDivert-LICENSE',
    'windivert-dependency.json'
)) {
    Copy-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $out $name)
}

$dependencyManifest = Join-Path $out 'windivert-dependency.json'
$manifest = [ordered]@{
    schema = 'arvectum.proxy.windows-windivert-build.v1'
    source_commit = (git rev-parse HEAD).Trim()
    version = '2.2.2'
    service = [ordered]@{
        filename = 'ArvectumProxyWinDivertRoutingService.exe'
        sha256 = Hash $serviceOut
    }
    dependency_manifest_sha256 = Hash $dependencyManifest
}
$manifestPath = Join-Path $out 'windivert-stack-build.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8

if ($env:GITHUB_OUTPUT) {
    "bundle_path=$out" >> $env:GITHUB_OUTPUT
}
Write-Output "ARVECTUM_WINDOWS_WINDIVERT_STACK_BUNDLE_READY path=$out"
