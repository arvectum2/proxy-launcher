<# APL-WIN-011 / Gate R6 Windows RC packaging and acceptance verifier. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$PortableZip,
    [Parameter(Mandatory)] [string]$SetupExe,
    [Parameter(Mandatory)] [string]$LifecycleEvidence,
    [string]$OutputPath = 'out\windows-rc-acceptance.json'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows RC acceptance must run on Windows.' }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
$versionCore = ($version -split '[-+]')[0]
$fileVersion = "$versionCore.0"
$PortableZip = (Resolve-Path -LiteralPath $PortableZip).Path
$SetupExe = (Resolve-Path -LiteralPath $SetupExe).Path
$LifecycleEvidence = (Resolve-Path -LiteralPath $LifecycleEvidence).Path
$expectedPortable = "Arvectum-Proxy-Launcher-$version-windows-x64-portable.zip"
$expectedSetup = "Arvectum-Proxy-Launcher-$version-windows-x64-setup.exe"
$checks = @()
$failures = @()

function Add-Check([string]$Id, [bool]$Pass, [string]$Detail) {
    $status = if ($Pass) { 'PASS' } else { 'FAIL' }
    $script:checks += [pscustomobject]@{ id=$Id; status=$status; detail=$Detail }
    if (-not $Pass) { $script:failures += $Id }
}
function Normalize-VersionInfo($Value) { return ([string]$Value).Trim() }

Add-Check 'artifact.portable.name' ((Split-Path $PortableZip -Leaf) -ceq $expectedPortable) (Split-Path $PortableZip -Leaf)
Add-Check 'artifact.setup.name' ((Split-Path $SetupExe -Leaf) -ceq $expectedSetup) (Split-Path $SetupExe -Leaf)
Add-Check 'artifact.synthetic.excluded' ((Split-Path $SetupExe -Leaf) -notmatch 'synthetic-predecessor') 'Synthetic lifecycle fixture must never be the accepted RC installer.'

$exe = Join-Path $root 'dist\Arvectum Proxy Launcher.exe'
Add-Check 'exe.exists' (Test-Path -LiteralPath $exe -PathType Leaf) $exe
if (Test-Path -LiteralPath $exe -PathType Leaf) {
    $info = (Get-Item -LiteralPath $exe).VersionInfo
    Add-Check 'exe.company' ([string]$info.CompanyName -ceq 'ООО «Арвектум»') ([string]$info.CompanyName)
    Add-Check 'exe.product' ([string]$info.ProductName -ceq 'Arvectum Proxy Launcher') ([string]$info.ProductName)
    Add-Check 'exe.description' ([string]$info.FileDescription -ceq 'Arvectum Proxy Launcher') ([string]$info.FileDescription)
    Add-Check 'exe.product_version' ([string]$info.ProductVersion -ceq $version) ([string]$info.ProductVersion)
    Add-Check 'exe.file_version' ([string]$info.FileVersion -ceq $fileVersion) ([string]$info.FileVersion)
    Add-Check 'exe.original_filename' ([string]$info.OriginalFilename -ceq 'Arvectum Proxy Launcher.exe') ([string]$info.OriginalFilename)
}

$setupInfo = (Get-Item -LiteralPath $SetupExe).VersionInfo
$setupCompany = Normalize-VersionInfo $setupInfo.CompanyName
$setupProduct = Normalize-VersionInfo $setupInfo.ProductName
$setupDescription = Normalize-VersionInfo $setupInfo.FileDescription
$setupProductVersion = Normalize-VersionInfo $setupInfo.ProductVersion
$setupFileVersion = Normalize-VersionInfo $setupInfo.FileVersion
Add-Check 'setup.company' ($setupCompany -ceq 'ООО «Арвектум»') $setupCompany
Add-Check 'setup.product' ($setupProduct -ceq 'Arvectum Proxy Launcher') $setupProduct
Add-Check 'setup.description' ($setupDescription -ceq 'Arvectum Proxy Launcher Windows Installer') $setupDescription
Add-Check 'setup.product_version' ($setupProductVersion -ceq $version) $setupProductVersion
Add-Check 'setup.file_version' ($setupFileVersion -ceq $fileVersion) $setupFileVersion

$buildResultPath = Join-Path $root 'out\build-result.json'
Add-Check 'portable.build_manifest.exists' (Test-Path -LiteralPath $buildResultPath -PathType Leaf) $buildResultPath
if (Test-Path -LiteralPath $buildResultPath -PathType Leaf) {
    $build = Get-Content -LiteralPath $buildResultPath -Raw | ConvertFrom-Json
    Add-Check 'portable.build_manifest.version' ([string]$build.version -ceq $version) ([string]$build.version)
    $actualZipHash = (Get-FileHash -LiteralPath $PortableZip -Algorithm SHA256).Hash.ToLowerInvariant()
    Add-Check 'portable.build_manifest.sha256' ([string]$build.zip_sha256 -ceq $actualZipHash) $actualZipHash
}

$temp = Join-Path $env:TEMP ("apl-win-011-" + [guid]::NewGuid().ToString('N'))
try {
    Expand-Archive -LiteralPath $PortableZip -DestinationPath $temp -Force

    $baseExpectedFiles = @(
        'Arvectum Proxy Launcher.exe',
        'README.txt',
        'diagnose_app_control.ps1',
        'run_p01_native_qa_v2.ps1',
        'SHA256SUMS.txt',
        'LICENSE.txt',
        'THIRD_PARTY_NOTICES.txt'
    )
    foreach ($required in $baseExpectedFiles) {
        $requiredPath = Join-Path $temp $required
        Add-Check "portable.required.$required" ((Test-Path -LiteralPath $requiredPath -PathType Leaf) -and ((Get-Item -LiteralPath $requiredPath -ErrorAction SilentlyContinue).Length -gt 0)) $required
    }

    $bundleRoot = Join-Path $temp 'THIRD_PARTY_LICENSES'
    $bundleManifestPath = Join-Path $bundleRoot 'manifest.json'
    $manifestExists = Test-Path -LiteralPath $bundleManifestPath -PathType Leaf
    Add-Check 'portable.licenses.manifest.exists' $manifestExists $bundleManifestPath

    $manifestAllowed = @()
    if ($manifestExists) {
        try {
            $licenseManifest = Get-Content -LiteralPath $bundleManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Add-Check 'portable.licenses.manifest.schema' ([string]$licenseManifest.schema -ceq 'arvectum.third-party-license-bundle.v1') ([string]$licenseManifest.schema)
            $requiredComponents = @('python','tcl','tk','pyinstaller')
            $manifestComponents = @($licenseManifest.components | ForEach-Object { [string]$_ })
            $componentsPass = @($requiredComponents | Where-Object { $_ -notin $manifestComponents }).Count -eq 0
            Add-Check 'portable.licenses.components' $componentsPass ($manifestComponents -join ', ')

            $licenseRecords = @($licenseManifest.files)
            Add-Check 'portable.licenses.records' ($licenseRecords.Count -gt 0) ([string]$licenseRecords.Count)
            foreach ($record in $licenseRecords) {
                $relative = [string]$record.bundle_path
                $component = [string]$record.component
                $expectedHash = ([string]$record.sha256).ToLowerInvariant()
                $safeRelative = ($relative -replace '/', '\')
                $fullPath = Join-Path $bundleRoot $safeRelative
                $pathSafe = $relative -and (-not [System.IO.Path]::IsPathRooted($relative)) -and ($relative -notmatch '(^|/|\\)\.\.($|/|\\)')
                $recordPass = $pathSafe -and ($component -in $requiredComponents) -and ($expectedHash -match '^[0-9a-f]{64}$') -and (Test-Path -LiteralPath $fullPath -PathType Leaf)
                if ($recordPass) {
                    $item = Get-Item -LiteralPath $fullPath
                    $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    $recordPass = ($item.Length -gt 0) -and ($actualHash -ceq $expectedHash)
                }
                Add-Check "portable.licenses.file.$component.$relative" $recordPass $relative
                if ($pathSafe) { $manifestAllowed += "THIRD_PARTY_LICENSES/$($relative -replace '\\','/')" }
            }
        } catch {
            Add-Check 'portable.licenses.manifest.parse' $false $_.Exception.Message
        }
    }

    # Gate R6 remains an exact-content gate: bundle children are not broadly
    # allowlisted. Only files enumerated and hash-bound by manifest.json are valid.
    # Path.GetRelativePath handles the Windows 8.3 short-path alias that hosted
    # runners can expose for %TEMP% (for example RUNNER~1 vs runneradmin).
    $expectedEntries = @($baseExpectedFiles | ForEach-Object { $_ }) + @('THIRD_PARTY_LICENSES/manifest.json') + @($manifestAllowed)
    $actualEntries = @(Get-ChildItem -LiteralPath $temp -File -Recurse | ForEach-Object {
        ([System.IO.Path]::GetRelativePath($temp, $_.FullName)) -replace '\\','/'
    } | Sort-Object)
    $expectedSorted = @($expectedEntries | Sort-Object)
    Add-Check 'portable.contents' (($actualEntries -join '|') -ceq ($expectedSorted -join '|')) ($actualEntries -join ', ')

    $packageExe = Join-Path $temp 'Arvectum Proxy Launcher.exe'
    if (Test-Path -LiteralPath $packageExe) {
        $packageExeHash = (Get-FileHash -LiteralPath $packageExe -Algorithm SHA256).Hash.ToLowerInvariant()
        $distExeHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
        Add-Check 'portable.exe.identity' ($packageExeHash -ceq $distExeHash) $packageExeHash
        $internalManifest = Get-Content -LiteralPath (Join-Path $temp 'SHA256SUMS.txt') -Raw
        Add-Check 'portable.internal_sha256' ($internalManifest -match ('^' + [regex]::Escape($packageExeHash) + '\s{2}Arvectum Proxy Launcher\.exe\s*$')) $internalManifest.Trim()
    }
    $portableReadme = Get-Content -LiteralPath (Join-Path $temp 'README.txt') -Raw
    Add-Check 'portable.readme.no_internal_milestone' ($portableReadme -notmatch '\bP0(?:\.\d+)?\b|\bRC\d*\b') 'Portable user README contains no engineering milestone labels.'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

$lifecycle = Get-Content -LiteralPath $LifecycleEvidence -Raw | ConvertFrom-Json
Add-Check 'lifecycle.schema' ([string]$lifecycle.schema -ceq 'arvectum.proxy.windows-rc-e2e.v2') ([string]$lifecycle.schema)
Add-Check 'lifecycle.result' ([string]$lifecycle.result -ceq 'PASS') ([string]$lifecycle.result)
foreach ($phase in @('fresh_install_smoke','fresh_uninstall','upgrade','repair','uninstall')) {
    $property = $lifecycle.phases.PSObject.Properties[$phase]
    $value = if ($null -eq $property) { '' } else { [string]$property.Value }
    Add-Check "lifecycle.$phase" ($value -ceq 'PASS') $value
}
Add-Check 'lifecycle.configuration_preserved' ($lifecycle.configuration_preserved -eq $true) ([string]$lifecycle.configuration_preserved)
Add-Check 'lifecycle.foreign_startup_preserved' ($lifecycle.foreign_startup_preserved -eq $true) ([string]$lifecycle.foreign_startup_preserved)

$requiredDocs = @(
    'INSTALL.txt',
    'APL-WIN-010_FINAL_EXECUTABLE_METADATA_WINDOWS_BRANDING.md',
    'APL-WIN-011_RELEASE_CANDIDATE_PACKAGING_ACCEPTANCE_MATRIX.md',
    'APL-WIN-012_WINDOWS_RC_E2E.md',
    'APL-WIN-013_WINDOWS_SUPPORTABILITY_INSTALL_DOCS.md',
    'GATE_R6_WINDOWS_PRODUCTIZATION.md'
)
foreach ($doc in $requiredDocs) {
    Add-Check "docs.$doc" (Test-Path -LiteralPath (Join-Path $root $doc) -PathType Leaf) $doc
}
$installText = Get-Content -LiteralPath (Join-Path $root 'INSTALL.txt') -Raw
Add-Check 'docs.install.no_internal_milestone' ($installText -notmatch '\bP0(?:\.\d+)?\b|\bRC\d*\b') 'INSTALL.txt contains no internal milestone labels.'

$releaseHashes = @(
    "$(Get-FileHash -LiteralPath $PortableZip -Algorithm SHA256 | Select-Object -ExpandProperty Hash | ForEach-Object { $_.ToLowerInvariant() })  $expectedPortable",
    "$(Get-FileHash -LiteralPath $SetupExe -Algorithm SHA256 | Select-Object -ExpandProperty Hash | ForEach-Object { $_.ToLowerInvariant() })  $expectedSetup"
)
$releaseHashPath = Join-Path $root 'out\windows-rc-SHA256SUMS.txt'
Set-Content -LiteralPath $releaseHashPath -Value $releaseHashes -Encoding ascii

$result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$evidence = [ordered]@{
    schema = 'arvectum.proxy.windows-rc-acceptance.v1'
    product = 'Arvectum Proxy Launcher'
    company = 'ООО «Арвектум»'
    version = $version
    result = $result
    portable = (Split-Path $PortableZip -Leaf)
    setup = (Split-Path $SetupExe -Leaf)
    sha256_manifest = (Split-Path $releaseHashPath -Leaf)
    checks = $checks
    failures = $failures
    signing = [ordered]@{
        production_embedded_signing_activated = $false
        boundary = 'Governed separately by APL-REL-009/APL-REL-010; branding metadata is not a signature.'
    }
}
$outputDir = Split-Path -Parent $OutputPath
if ($outputDir) { New-Item -ItemType Directory -Force -Path $outputDir | Out-Null }
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8
if ($failures.Count -ne 0) {
    throw "Windows RC acceptance FAIL: $($failures -join ', ')"
}
Write-Host "APL-WIN-011 / Gate R6 Windows RC acceptance PASS. Evidence: $OutputPath"