<#
.SYNOPSIS
    Acquire and verify the exact APL-IP-002-WIN Windows x64 build wheelhouse.
.DESCRIPTION
    This is the only network-acquisition step for the Python build toolchain.
    The interpreter running pip is only an acquisition transport. pip is explicitly
    targeted at the governed CPython/Windows build runtime using --platform,
    --python-version, --implementation and --abi, so the acquisition interpreter
    does not need to equal BUILD_PYTHON_VERSION.

    pip downloads only binary wheels named by requirements-build.windows-x64.hashes.txt
    and verifies every file against the committed SHA256 hashes. PowerShell then
    independently enforces the exact eight approved filenames and records hashes.
    The resulting directory can be copied to Arvectum-controlled storage and consumed
    by clean_build_windows.ps1 with -WheelhousePath, where package-index access is disabled.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PythonExecutable = "python.exe",

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$HashLock = Join-Path $RepoRoot "requirements-build.windows-x64.hashes.txt"
if (-not (Test-Path -LiteralPath $HashLock)) {
    throw "Missing hash lock: $HashLock"
}

$Python = (Get-Command $PythonExecutable -ErrorAction Stop).Source
$InterpreterCheck = & $Python -c "import json,platform,sys; print(json.dumps({'implementation':platform.python_implementation(),'version':'.'.join(map(str,sys.version_info[:3])),'machine':platform.machine(),'bits':platform.architecture()[0]}))"
if ($LASTEXITCODE -ne 0 -or -not $InterpreterCheck) {
    throw "Unable to inspect wheelhouse acquisition Python"
}
$Acquisition = $InterpreterCheck | Select-Object -Last 1 | ConvertFrom-Json
if ($Acquisition.implementation -ne 'CPython') {
    throw "Wheelhouse acquisition transport must be CPython; got $($Acquisition.implementation) $($Acquisition.version)"
}

$PipVersion = & $Python -c "import pip; print(pip.__version__)"
if ($LASTEXITCODE -ne 0 -or -not $PipVersion) {
    throw "Wheelhouse acquisition requires pip to be available in $Python"
}
$PipVersion = ($PipVersion | Select-Object -Last 1).Trim()

$ExpectedVersion = (Get-Content -LiteralPath (Join-Path $RepoRoot "BUILD_PYTHON_VERSION") -Raw).Trim()
$VersionParts = $ExpectedVersion.Split('.')
if ($VersionParts.Count -lt 2) {
    throw "Invalid BUILD_PYTHON_VERSION: $ExpectedVersion"
}
$TargetAbi = "cp$($VersionParts[0])$($VersionParts[1])"
$TargetPipPlatform = 'win_amd64'
$TargetImplementation = 'cp'

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $RepoRoot "artifact\windows-wheelhouse"
}
$Wheelhouse = [System.IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $Wheelhouse) {
    Remove-Item -LiteralPath $Wheelhouse -Recurse -Force
}
New-Item -ItemType Directory -Path $Wheelhouse -Force | Out-Null

Write-Host "Acquisition transport: CPython $($Acquisition.version) $($Acquisition.bits), pip $PipVersion"
Write-Host "Target wheel tags: CPython $ExpectedVersion / $TargetPipPlatform / $TargetImplementation / $TargetAbi"
Write-Host "Downloading exact hash-locked Windows x64 wheels to $Wheelhouse..."
& $Python -m pip download `
    --dest $Wheelhouse `
    --only-binary=:all: `
    --no-deps `
    --require-hashes `
    --platform $TargetPipPlatform `
    --python-version $ExpectedVersion `
    --implementation $TargetImplementation `
    --abi $TargetAbi `
    -r $HashLock
if ($LASTEXITCODE -ne 0) {
    throw "Hash-verified cross-target wheelhouse acquisition failed for CPython $ExpectedVersion / $TargetPipPlatform / $TargetAbi"
}

$Wheels = @(Get-ChildItem -LiteralPath $Wheelhouse -File -Filter "*.whl" | Sort-Object Name)
if ($Wheels.Count -ne 8) {
    throw "Expected exactly 8 approved wheels; found $($Wheels.Count)"
}

$ExpectedNames = @(
    'altgraph-0.17.5-py2.py3-none-any.whl',
    'packaging-26.3-py3-none-any.whl',
    'pefile-2024.8.26-py3-none-any.whl',
    'pip-26.1.2-py3-none-any.whl',
    'pyinstaller-6.22.0-py3-none-win_amd64.whl',
    'pyinstaller_hooks_contrib-2026.6-py3-none-any.whl',
    'pywin32_ctypes-0.2.3-py3-none-any.whl',
    'setuptools-84.1.0-py3-none-any.whl'
)
$ActualNames = @($Wheels | Select-Object -ExpandProperty Name)
foreach ($name in $ExpectedNames) {
    if ($ActualNames -notcontains $name) { throw "Missing approved wheel: $name" }
}
foreach ($name in $ActualNames) {
    if ($ExpectedNames -notcontains $name) { throw "Unexpected wheel in controlled wheelhouse: $name" }
}

$ExpectedHashes = @{}
$currentPackage = $null
foreach ($line in Get-Content -LiteralPath $HashLock) {
    if ($line -match '^([A-Za-z0-9_.-]+)==([^\s\\]+)') {
        $currentPackage = $Matches[1].ToLowerInvariant().Replace('_','-')
    } elseif ($currentPackage -and $line -match '--hash=sha256:([0-9a-fA-F]{64})') {
        $ExpectedHashes[$currentPackage] = $Matches[1].ToLowerInvariant()
        $currentPackage = $null
    }
}
if ($ExpectedHashes.Count -ne 8) {
    throw "Expected 8 hashes in committed Windows wheel lock; found $($ExpectedHashes.Count)"
}

$Files = foreach ($wheel in $Wheels) {
    $NormalizedName = ($wheel.Name -split '-')[0].ToLowerInvariant().Replace('_','-')
    if (-not $ExpectedHashes.ContainsKey($NormalizedName)) {
        throw "No committed hash found for wheel: $($wheel.Name)"
    }
    $ActualHash = (Get-FileHash -LiteralPath $wheel.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ActualHash -ne $ExpectedHashes[$NormalizedName]) {
        throw "SHA256 mismatch after download for $($wheel.Name): expected $($ExpectedHashes[$NormalizedName]), got $ActualHash"
    }
    [ordered]@{
        name   = $wheel.Name
        bytes  = $wheel.Length
        sha256 = $ActualHash
    }
}

$GitCommit = "unknown"
try {
    $candidate = (git -C $RepoRoot rev-parse HEAD 2>$null)
    if ($candidate) { $GitCommit = $candidate.Trim() }
} catch {}

$Manifest = [ordered]@{
    schema_version                  = 2
    purpose                         = "APL-IP-002-WIN-R1/R2 controlled Windows x64 Python build wheelhouse"
    source_channel                  = "PyPI acquisition verified by committed SHA256 requirements"
    python_version                  = $ExpectedVersion
    python_architecture             = "64bit"
    target_platform                 = "windows-x64"
    target_pip_platform             = $TargetPipPlatform
    target_python_implementation    = "CPython"
    target_pip_implementation       = $TargetImplementation
    target_abi                      = $TargetAbi
    acquisition_python_version      = [string]$Acquisition.version
    acquisition_python_architecture = [string]$Acquisition.bits
    acquisition_python_machine      = [string]$Acquisition.machine
    acquisition_pip_version         = $PipVersion
    hash_lock_sha256                = (Get-FileHash -LiteralPath $HashLock -Algorithm SHA256).Hash.ToLowerInvariant()
    source_commit                   = $GitCommit
    wheel_count                     = $Wheels.Count
    wheels                          = @($Files)
}
$ManifestPath = Join-Path $Wheelhouse "wheelhouse-manifest.json"
$Manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ManifestPath -Encoding utf8

Write-Host "Wheelhouse verification PASS: $($Wheels.Count) exact wheels for CPython $ExpectedVersion Windows x64"
Write-Host "Manifest: $ManifestPath"
Write-Output $Wheelhouse
