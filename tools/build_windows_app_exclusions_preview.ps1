[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$FoundationArtifactDirectory,
    [string]$PythonExecutable = 'python',
    [string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Windows app-exclusions preview must be built on Windows.'
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root
$version = (Get-Content VERSION -Raw).Trim()
$sourceCommit = (git rev-parse HEAD).Trim()
if (git status --porcelain) {
    throw 'Preview release build requires a clean git worktree.'
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $root ("out\windows-app-exclusions-preview-" + $version)
}
$foundationSource = (Resolve-Path -LiteralPath $FoundationArtifactDirectory).Path
$tempFoundation = Join-Path ([IO.Path]::GetTempPath()) ('apl-preview-foundation-' + [Guid]::NewGuid().ToString('N'))
$tempWork = Join-Path ([IO.Path]::GetTempPath()) ('apl-preview-build-' + [Guid]::NewGuid().ToString('N'))
$cert = $null

function Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Find-SignTool {
    $kitsRoot = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots' -ErrorAction Stop).KitsRoot10
    $candidate = Get-ChildItem (Join-Path $kitsRoot 'bin') -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $candidate) { throw 'x64 signtool.exe was not found.' }
    return $candidate
}

try {
    Copy-Item -LiteralPath $foundationSource -Destination $tempFoundation -Recurse
    New-Item -ItemType Directory -Path $tempWork -Force | Out-Null

    # clean_build_windows.ps1 deletes repo out/, so the hosted native artifact
    # is staged outside the repository before invoking the canonical build.
    & (Join-Path $root 'tools\clean_build_windows.ps1') -PythonExecutable $PythonExecutable
    if ($LASTEXITCODE -ne 0) { throw 'Canonical Windows application build failed.' }

    $portable = Join-Path $root ("out\Arvectum-Proxy-Launcher-$version-windows-x64-portable.zip")
    $buildResult = Join-Path $root 'out\build-result.json'
    $applicationExe = Join-Path $root 'dist\Arvectum Proxy Launcher.exe'
    foreach ($required in @($portable,$buildResult,$applicationExe)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Canonical application build output is missing: $required"
        }
    }

    $driverPackageSource = Join-Path $tempFoundation 'out\windows-driver-submission'
    $foundationManifestPath = Join-Path $driverPackageSource 'driver-submission-manifest.json'
    if (-not (Test-Path -LiteralPath $foundationManifestPath -PathType Leaf)) {
        throw 'Hosted foundation artifact has no driver-submission-manifest.json.'
    }
    $foundationManifest = Get-Content -LiteralPath $foundationManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]$foundationManifest.source_commit -cne $sourceCommit) {
        throw "Hosted foundation artifact source_commit does not match preview HEAD: $($foundationManifest.source_commit) != $sourceCommit"
    }
    $serviceSource = Join-Path $tempFoundation 'ArvectumProxyRoutingService.exe'
    $toolSource = Join-Path $tempFoundation 'ArvectumDriverPackageTool.exe'
    foreach ($required in @(
        (Join-Path $driverPackageSource 'ArvectumProxyRoutingCallout.inf'),
        (Join-Path $driverPackageSource 'ArvectumProxyRoutingCallout.cat'),
        (Join-Path $driverPackageSource 'ArvectumProxyRoutingCallout.sys'),
        $serviceSource,
        $toolSource
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Hosted foundation artifact is incomplete: $required"
        }
    }

    $driverWork = Join-Path $tempWork 'driver-package'
    Copy-Item -LiteralPath $driverPackageSource -Destination $driverWork -Recurse
    $previewCertificate = Join-Path $tempWork 'ArvectumProxyRoutingPreview.cer'
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=Arvectum Windows App Exclusions Preview' -CertStoreLocation 'Cert:\CurrentUser\My' -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddMonths(6)
    Export-Certificate -Cert $cert -FilePath $previewCertificate | Out-Null

    $signtool = Find-SignTool
    $catalog = Join-Path $driverWork 'ArvectumProxyRoutingCallout.cat'
    & $signtool sign /fd SHA256 /sha1 $cert.Thumbprint /s My $catalog
    if ($LASTEXITCODE -ne 0) { throw 'Preview driver catalog signing failed.' }
    $catalogSig = Get-AuthenticodeSignature -LiteralPath $catalog
    if (-not $catalogSig.SignerCertificate -or $catalogSig.SignerCertificate.Thumbprint -cne $cert.Thumbprint) {
        throw 'Preview catalog signer does not match generated preview certificate.'
    }

    $nativeBundle = Join-Path $tempWork 'native-bundle'
    $bundleArgs = @{
        DriverPackageDirectory = $driverWork
        ServicePath = $serviceSource
        DriverPackageToolPath = $toolSource
        SigningMode = 'Test'
        OutputDirectory = $nativeBundle
    }
    & (Join-Path $root 'tools\build_windows_native_stack_bundle.ps1') @bundleArgs
    if ($LASTEXITCODE -ne 0) { throw 'Preview native bundle build failed.' }

    $installerArgs = @{
        PythonExecutable = $PythonExecutable
        UseExistingPayload = $true
        ApplicationExe = $applicationExe
        PortableZip = $portable
        BuildResultPath = $buildResult
        NativeStackBundle = $nativeBundle
        AllowTestNativeStack = $true
        WindowsAppExclusionsPreview = $true
    }
    & (Join-Path $root 'tools\build_windows_installer.ps1') @installerArgs
    if ($LASTEXITCODE -ne 0) { throw 'Preview installer build failed.' }

    $setup = Join-Path $root ("out\installer\Arvectum-Proxy-Launcher-$version-windows-x64-setup-preview.exe")
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
        throw "Preview setup was not produced: $setup"
    }
    & $signtool sign /fd SHA256 /sha1 $cert.Thumbprint /s My $setup
    if ($LASTEXITCODE -ne 0) { throw 'Preview setup signing failed.' }
    $setupSig = Get-AuthenticodeSignature -LiteralPath $setup
    if (-not $setupSig.SignerCertificate -or $setupSig.SignerCertificate.Thumbprint -cne $cert.Thumbprint) {
        throw 'Preview setup signer does not match generated preview certificate.'
    }

    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $setupOut = Join-Path $OutputDirectory (Split-Path $setup -Leaf)
    $certOut = Join-Path $OutputDirectory 'ArvectumProxyRoutingPreview.cer'
    $helperOut = Join-Path $OutputDirectory 'windows_preview_mode_helper.ps1'
    Copy-Item -LiteralPath $setup -Destination $setupOut
    Copy-Item -LiteralPath $previewCertificate -Destination $certOut
    Copy-Item -LiteralPath (Join-Path $root 'installer\windows_preview_mode_helper.ps1') -Destination $helperOut

    $enableCmd = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows_preview_mode_helper.ps1" -Action Enable -CertificatePath "%~dp0ArvectumProxyRoutingPreview.cer"
set RC=%ERRORLEVEL%
if "%RC%"=="3010" (
  echo.
  echo Preview mode enabled. Restart Windows, then run the setup-preview.exe file.
  pause
  exit /b 0
)
if not "%RC%"=="0" (
  echo.
  echo Could not enable Arvectum preview mode. Exit code: %RC%
  pause
  exit /b %RC%
)
echo.
echo Preview mode is already active. You can run setup-preview.exe now.
pause
'@
    $enableCmd | Set-Content -LiteralPath (Join-Path $OutputDirectory 'Enable-App-Exclusions-Preview.cmd') -Encoding ascii

    $disableCmd = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows_preview_mode_helper.ps1" -Action Disable
set RC=%ERRORLEVEL%
if not "%RC%"=="0" (
  echo Preview cleanup failed. Exit code: %RC%
  pause
  exit /b %RC%
)
echo Preview mode disabled. Restart Windows if test mode was owned by this preview.
pause
'@
    $disableCmd | Set-Content -LiteralPath (Join-Path $OutputDirectory 'Disable-App-Exclusions-Preview.cmd') -Encoding ascii

    $readme = @"
# Arvectum Proxy Launcher $version - Windows App Exclusions Preview

This is a preview build for testing per-application exclusions before Microsoft production driver certification.

Install:
1. Run Enable-App-Exclusions-Preview.cmd and approve the Windows administrator prompt.
2. If it says restart is required, restart Windows.
3. Run Arvectum-Proxy-Launcher-$version-windows-x64-setup-preview.exe.
4. Open Arvectum Proxy Launcher -> Settings -> Application exclusions and select .exe files that must bypass the proxy.

The preview uses Windows test-signing mode and a public test certificate. It is not the Microsoft-certified production driver release.

Uninstall:
- Use the normal Arvectum Proxy Launcher uninstaller. It removes the native stack and owned preview-mode state.
- Disable-App-Exclusions-Preview.cmd is included as a recovery/cleanup action.

Source commit: $sourceCommit
Preview certificate thumbprint: $($cert.Thumbprint)
"@
    $readme | Set-Content -LiteralPath (Join-Path $OutputDirectory 'README-PREVIEW.md') -Encoding utf8

    $manifest = [ordered]@{
        schema = 'arvectum.proxy.windows-app-exclusions-preview.v1'
        version = $version
        source_commit = $sourceCommit
        generated_utc = [DateTime]::UtcNow.ToString('o')
        setup_filename = (Split-Path $setupOut -Leaf)
        setup_sha256 = Hash $setupOut
        preview_certificate_filename = (Split-Path $certOut -Leaf)
        preview_certificate_sha256 = Hash $certOut
        preview_certificate_thumbprint = $cert.Thumbprint
        helper_sha256 = Hash $helperOut
        requires_windows_testsigning = $true
        production_certified = $false
    }
    $manifestPath = Join-Path $OutputDirectory 'preview-manifest.json'
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8

    $sumLines = Get-ChildItem -LiteralPath $OutputDirectory -File |
        Sort-Object Name |
        ForEach-Object { '{0}  {1}' -f (Hash $_.FullName),$_.Name }
    $sumLines | Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Encoding ascii

    $zipPath = Join-Path (Split-Path $OutputDirectory -Parent) ("Arvectum-Proxy-Launcher-$version-windows-x64-app-exclusions-preview.zip")
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $OutputDirectory '*') -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Output ("ARVECTUM_WINDOWS_APP_EXCLUSIONS_PREVIEW_READY path={0} zip={1} setup_sha256={2} certificate={3}" -f $OutputDirectory,$zipPath,$manifest.setup_sha256,$cert.Thumbprint)
} finally {
    if ($null -ne $cert) {
        Remove-Item -LiteralPath ("Cert:\CurrentUser\My\{0}" -f $cert.Thumbprint) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $tempFoundation -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempWork -Recurse -Force -ErrorAction SilentlyContinue
}
