[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DriverPath,
    [Parameter(Mandatory=$true)][string]$PdbPath,
    [string]$InfTemplate = (Join-Path $PSScriptRoot '..\native\windows_routing\ArvectumProxyRoutingCallout.inf.in'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\out\windows-driver-submission'),
    [string]$InfVerifPath,
    [string]$Inf2CatPath,
    [string]$OsTargets = '10_19H1_X64,10_VB_X64,10_CO_X64,10_NI_X64,10_GE_X64,10_25H2_X64'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

$driver = (Resolve-Path -LiteralPath $DriverPath).Path
$pdb = (Resolve-Path -LiteralPath $PdbPath).Path
$template = (Resolve-Path -LiteralPath $InfTemplate).Path
$version = (Get-Content VERSION -Raw).Trim()
if ($version -notmatch '^(?<maj>\d+)\.(?<min>\d+)\.(?<patch>\d+)') {
    throw "VERSION is not a numeric semantic version: $version"
}
$driverVersion = "$($Matches.maj).$($Matches.min).$($Matches.patch).0"
$driverDate = [DateTime]::UtcNow.ToString('MM/dd/yyyy')

Remove-Item -LiteralPath $OutputDirectory -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
Copy-Item -LiteralPath $driver -Destination (Join-Path $OutputDirectory 'ArvectumProxyRoutingCallout.sys')
Copy-Item -LiteralPath $pdb -Destination (Join-Path $OutputDirectory 'ArvectumProxyRoutingCallout.pdb')

$infText = Get-Content -LiteralPath $template -Raw
$infText = $infText.Replace('@DRIVER_DATE@', $driverDate).Replace('@DRIVER_VERSION@', $driverVersion)
$infPath = Join-Path $OutputDirectory 'ArvectumProxyRoutingCallout.inf'
[IO.File]::WriteAllText($infPath, $infText, [Text.UTF8Encoding]::new($false))

if (-not $InfVerifPath) {
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    foreach ($base in @((Join-Path $programFilesX86 'Windows Kits\10\Tools'), (Join-Path $programFilesX86 'Windows Kits\10\bin'))) {
        if (-not (Test-Path -LiteralPath $base)) { continue }
        $InfVerifPath = Get-ChildItem $base -Filter infverif.exe -Recurse -ErrorAction SilentlyContinue |
            Where-Object FullName -Match '\\x64\\infverif\.exe$' |
            Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        if ($InfVerifPath) { break }
    }
}
$infverif = [ordered]@{ available = $false; path = $null; exit_code = $null }
if ($InfVerifPath -and (Test-Path -LiteralPath $InfVerifPath -PathType Leaf)) {
    $infverif.available = $true
    $infverif.path = (Resolve-Path -LiteralPath $InfVerifPath).Path
    & $infverif.path /v $infPath
    $infverif.exit_code = $LASTEXITCODE
    if ($LASTEXITCODE -ne 0) { throw "InfVerif failed with exit code $LASTEXITCODE" }
}

if (-not $Inf2CatPath) {
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    foreach ($base in @((Join-Path $programFilesX86 'Windows Kits\10\bin'), (Join-Path $programFilesX86 'Windows Kits\10\Tools'))) {
        if (-not (Test-Path -LiteralPath $base)) { continue }
        $Inf2CatPath = Get-ChildItem $base -Filter inf2cat.exe -Recurse -ErrorAction SilentlyContinue |
            Where-Object FullName -Match '\\x64\\inf2cat\.exe$' |
            Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        if ($Inf2CatPath) { break }
    }
}
if (-not $Inf2CatPath -or -not (Test-Path -LiteralPath $Inf2CatPath -PathType Leaf)) {
    throw 'Inf2Cat.exe is required to produce the canonical driver package catalog.'
}
$Inf2CatPath = (Resolve-Path -LiteralPath $Inf2CatPath).Path
& $Inf2CatPath "/driver:$OutputDirectory" "/os:$OsTargets" /uselocaltime /verbose
$inf2catExit = $LASTEXITCODE
if ($inf2catExit -ne 0) { throw "Inf2Cat failed with exit code $inf2catExit" }
$catalogPath = Join-Path $OutputDirectory 'ArvectumProxyRoutingCallout.cat'
if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw 'Inf2Cat completed without producing ArvectumProxyRoutingCallout.cat.'
}

$manifest = [ordered]@{
    schema = 'arvectum.proxy.windows-driver-submission.v1'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    source_commit = (git rev-parse HEAD).Trim()
    version = $version
    driver_version = $driverVersion
    driver_date = $driverDate
    architecture = 'x64'
    release_signing_path = 'microsoft-hardware-dashboard-whcp-hlk'
    attestation_release_allowed = $false
    files = [ordered]@{
        sys = [ordered]@{ name='ArvectumProxyRoutingCallout.sys'; sha256=Hash (Join-Path $OutputDirectory 'ArvectumProxyRoutingCallout.sys') }
        pdb = [ordered]@{ name='ArvectumProxyRoutingCallout.pdb'; sha256=Hash (Join-Path $OutputDirectory 'ArvectumProxyRoutingCallout.pdb') }
        inf = [ordered]@{ name='ArvectumProxyRoutingCallout.inf'; sha256=Hash $infPath }
        catalog = [ordered]@{ name='ArvectumProxyRoutingCallout.cat'; sha256=Hash $catalogPath }
    }
    infverif = $infverif
    inf2cat = [ordered]@{
        path = $Inf2CatPath
        exit_code = $inf2catExit
        os_targets = $OsTargets
    }
}
$manifestPath = Join-Path $OutputDirectory 'driver-submission-manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output "ARVECTUM_WINDOWS_DRIVER_SUBMISSION_READY path=$OutputDirectory"
