[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Install", "Status", "Uninstall")]
    [string]$Action,
    [string]$SourceDirectory,
    [string]$SourceCommit = ""
)

$ErrorActionPreference = "Stop"
$ServiceName = "ArvectumProxyWinDivertRouting"
$ServiceDisplayName = "Arvectum Proxy Launcher WinDivert Routing"
$ServiceFile = "ArvectumProxyWinDivertRoutingService.exe"
$WinDivertDriverServiceName = "WinDivert"
$Version = "2.2.2"
$ExpectedDriverHash = "8DA085332782708D8767BCACE5327A6EC7283C17CFB85E40B03CD2323A90DDC2"
$ExpectedDllHash = "C1E060EE19444A259B2162F8AF0F3FE8C4428A1C6F694DCE20DE194AC8D7D9A2"
$ExpectedLicenseHash = "14A0CB5214D536E4FDAE6AA3F5696F981EEDA106CD026E9794BBA489EE79D628"
$ExpectedSigner = "043589F75FCE2795E7F2CC3E526D46784D5DDAB3"

$ProductRoot = Join-Path $env:ProgramData "Arvectum\ProxyLauncher"
$InstallRoot = Join-Path $ProductRoot "WinDivert"
$InstalledDriverPath = Join-Path $InstallRoot "WinDivert64.sys"
$MarkerPath = Join-Path $ProductRoot "windivert-stack.json"

function Assert-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $admin = [Security.Principal.WindowsBuiltInRole]::Administrator
    if (-not $principal.IsInRole($admin)) {
        throw "WinDivert service lifecycle requires Administrator elevation."
    }
}

function Assert-Sha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required WinDivert service file is absent: $Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $Expected.ToUpperInvariant()) {
        throw "SHA256 mismatch for $Path. Expected $Expected, got $actual."
    }
    return $actual
}

function Get-OwnedService {
    return Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
}

function Remove-OwnedService {
    $service = Get-OwnedService
    if ($null -eq $service) {
        return
    }
    if ($service.Status -ne [ServiceProcess.ServiceControllerStatus]::Stopped) {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        try {
            (Get-Service -Name $ServiceName).WaitForStatus(
                [ServiceProcess.ServiceControllerStatus]::Stopped,
                [TimeSpan]::FromSeconds(15)
            )
        }
        catch {
            throw "Arvectum WinDivert routing service did not stop."
        }
    }

    & sc.exe delete $ServiceName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not delete Arvectum WinDivert routing service."
    }
    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ((Test-Path -LiteralPath $registryPath) -and
           [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    if (Test-Path -LiteralPath $registryPath) {
        throw "Arvectum WinDivert routing service deletion is pending."
    }
}

function Normalize-DriverImagePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $value = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if ($value.StartsWith('\??\', [StringComparison]::Ordinal)) {
        $value = $value.Substring(4)
    }
    try {
        return [IO.Path]::GetFullPath($value).TrimEnd('\').ToLowerInvariant()
    }
    catch {
        return $value.TrimEnd('\').ToLowerInvariant()
    }
}

function Get-WinDivertDriverRegistryPath {
    return "HKLM:\SYSTEM\CurrentControlSet\Services\$WinDivertDriverServiceName"
}

function Get-WinDivertDriverImagePath {
    $registryPath = Get-WinDivertDriverRegistryPath
    if (-not (Test-Path -LiteralPath $registryPath)) {
        return $null
    }
    return [string](Get-ItemPropertyValue -LiteralPath $registryPath -Name ImagePath -ErrorAction Stop)
}

function Assert-NoForeignWinDivertDriverService {
    $imagePath = Get-WinDivertDriverImagePath
    if ([string]::IsNullOrWhiteSpace($imagePath)) {
        return
    }
    $actual = Normalize-DriverImagePath -Path $imagePath
    $expected = Normalize-DriverImagePath -Path $InstalledDriverPath
    if ($actual -ne $expected) {
        throw (
            "A foreign WinDivert driver service is already registered at '{0}'. " +
            "Arvectum will not stop, delete, or reuse it." -f $imagePath
        )
    }
}

function Remove-OwnedWinDivertDriverService {
    $imagePath = Get-WinDivertDriverImagePath
    if ([string]::IsNullOrWhiteSpace($imagePath)) {
        return
    }

    $actual = Normalize-DriverImagePath -Path $imagePath
    $expected = Normalize-DriverImagePath -Path $InstalledDriverPath
    if ($actual -ne $expected) {
        return
    }

    $service = Get-Service -Name $WinDivertDriverServiceName -ErrorAction SilentlyContinue
    if ($null -ne $service -and
        $service.Status -ne [ServiceProcess.ServiceControllerStatus]::Stopped) {
        Stop-Service -Name $WinDivertDriverServiceName -Force -ErrorAction Stop
        (Get-Service -Name $WinDivertDriverServiceName).WaitForStatus(
            [ServiceProcess.ServiceControllerStatus]::Stopped,
            [TimeSpan]::FromSeconds(15)
        )
    }

    & sc.exe delete $WinDivertDriverServiceName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not delete owned WinDivert driver service."
    }

    $registryPath = Get-WinDivertDriverRegistryPath
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ((Test-Path -LiteralPath $registryPath) -and
           [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    if (Test-Path -LiteralPath $registryPath) {
        throw "Owned WinDivert driver service deletion is pending."
    }
}

function Read-DependencyManifest {
    param([Parameter(Mandatory = $true)][string]$Directory)
    $manifestPath = Join-Path $Directory "windivert-dependency.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "WinDivert dependency manifest is absent."
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.schema -cne "arvectum.proxy.windivert-dependency.v1" -or
        [string]$manifest.version -cne $Version) {
        throw "WinDivert dependency manifest identity is invalid."
    }
    return $manifest
}

function Verify-Source {
    param([Parameter(Mandatory = $true)][string]$Directory)
    $resolved = (Resolve-Path -LiteralPath $Directory).Path
    $manifest = Read-DependencyManifest -Directory $resolved

    $servicePath = Join-Path $resolved $ServiceFile
    $dllPath = Join-Path $resolved "WinDivert.dll"
    $driverPath = Join-Path $resolved "WinDivert64.sys"
    $licensePath = Join-Path $resolved "WinDivert-LICENSE"

    if (-not (Test-Path -LiteralPath $servicePath -PathType Leaf)) {
        throw "Arvectum WinDivert routing service executable is absent."
    }
    $serviceHash = (Get-FileHash -LiteralPath $servicePath -Algorithm SHA256).Hash.ToUpperInvariant()
    $dllHash = Assert-Sha256 -Path $dllPath -Expected $ExpectedDllHash
    $driverHash = Assert-Sha256 -Path $driverPath -Expected $ExpectedDriverHash
    $licenseHash = Assert-Sha256 -Path $licensePath -Expected $ExpectedLicenseHash

    if ([string]$manifest.files."WinDivert.dll" -cne $dllHash -or
        [string]$manifest.files."WinDivert64.sys" -cne $driverHash -or
        [string]$manifest.files."WinDivert-LICENSE" -cne $licenseHash) {
        throw "WinDivert dependency manifest hashes do not match staged files."
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $driverPath
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate) {
        throw "WinDivert64.sys Authenticode verification failed."
    }
    $signer = $signature.SignerCertificate.Thumbprint.ToUpperInvariant()
    if ($signer -ne $ExpectedSigner -or
        [string]$manifest.driver_signer_thumbprint -cne $ExpectedSigner) {
        throw "WinDivert64.sys signer identity is not pinned."
    }

    return [ordered]@{
        source = $resolved
        service_sha256 = $serviceHash
        dll_sha256 = $dllHash
        driver_sha256 = $driverHash
        license_sha256 = $licenseHash
        driver_signer_thumbprint = $signer
    }
}

function Write-Marker {
    param([Parameter(Mandatory = $true)]$Verified)

    New-Item -ItemType Directory -Path $ProductRoot -Force | Out-Null
    $payload = [ordered]@{
        schema = "arvectum.proxy.windows-windivert-stack.v1"
        version = $Version
        source_commit = [string]$SourceCommit
        install_root = $InstallRoot
        service = [ordered]@{
            name = $ServiceName
            filename = $ServiceFile
            sha256 = [string]$Verified.service_sha256
        }
        dependency = [ordered]@{
            dll_sha256 = [string]$Verified.dll_sha256
            driver_sha256 = [string]$Verified.driver_sha256
            license_sha256 = [string]$Verified.license_sha256
            driver_signer_thumbprint = [string]$Verified.driver_signer_thumbprint
        }
    }
    $json = $payload | ConvertTo-Json -Depth 6
    $temporary = "$MarkerPath.tmp-$PID"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($temporary, $json, $utf8)
    Move-Item -LiteralPath $temporary -Destination $MarkerPath -Force
}

function Install-Stack {
    if (-not $SourceDirectory) {
        throw "SourceDirectory is required for Install."
    }
    Assert-Elevated
    $verified = Verify-Source -Directory $SourceDirectory

    Assert-NoForeignWinDivertDriverService
    Remove-OwnedService
    Remove-OwnedWinDivertDriverService
    if (Test-Path -LiteralPath $InstallRoot) {
        Remove-Item -LiteralPath $InstallRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

    foreach ($name in @(
        $ServiceFile,
        "WinDivert.dll",
        "WinDivert64.sys",
        "WinDivert-LICENSE",
        "windivert-dependency.json"
    )) {
        Copy-Item -LiteralPath (Join-Path $verified.source $name) -Destination (Join-Path $InstallRoot $name) -Force
    }

    try {
        $servicePath = Join-Path $InstallRoot $ServiceFile
        $serviceArgs = @{
            Name = $ServiceName
            BinaryPathName = ('"{0}"' -f $servicePath)
            DisplayName = $ServiceDisplayName
            Description = "Privileged per-application routing service for Arvectum Proxy Launcher."
            StartupType = "Automatic"
            DependsOn = "BFE"
        }
        New-Service @serviceArgs | Out-Null
        Start-Service -Name $ServiceName
        (Get-Service -Name $ServiceName).WaitForStatus(
            [ServiceProcess.ServiceControllerStatus]::Running,
            [TimeSpan]::FromSeconds(15)
        )
        Write-Marker -Verified $verified
    }
    catch {
        try { Remove-OwnedService } catch {}
        Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $MarkerPath -Force -ErrorAction SilentlyContinue
        throw
    }

    Write-Output (
        "ARVECTUM_WINDIVERT_STACK_INSTALLED service={0} version={1}" -f
        $ServiceName, $Version
    )
}

function Uninstall-Stack {
    Assert-Elevated
    Remove-OwnedService
    Remove-OwnedWinDivertDriverService
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $MarkerPath -Force -ErrorAction SilentlyContinue
    Write-Output "ARVECTUM_WINDIVERT_STACK_UNINSTALLED"
}

function Show-Status {
    $service = Get-OwnedService
    $marker = Test-Path -LiteralPath $MarkerPath -PathType Leaf
    $state = if ($null -eq $service) { "Absent" } else { [string]$service.Status }
    Write-Output (
        "ARVECTUM_WINDIVERT_STACK_STATUS marker={0} service={1}" -f
        $marker, $state
    )
}

switch ($Action) {
    "Install" { Install-Stack }
    "Uninstall" { Uninstall-Stack }
    "Status" { Show-Status }
}

