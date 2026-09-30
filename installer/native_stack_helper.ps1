[CmdletBinding()]
param(
    [ValidateSet('Preflight','Install','Uninstall','Status')]
    [string]$Action = 'Status',
    [string]$PayloadRoot,
    [string]$InstallRoot = (Join-Path $env:ProgramFiles 'Arvectum\ProxyLauncherNative'),
    [switch]$AllowTestBundle,
    [switch]$Elevated
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DriverService = 'ArvectumProxyRoutingCallout'
$RoutingService = 'ArvectumProxyRouting'
$DriverFile = 'ArvectumProxyRoutingCallout.sys'
$DriverInf = 'ArvectumProxyRoutingCallout.inf'
$DriverCatalog = 'ArvectumProxyRoutingCallout.cat'
$ServiceFile = 'ArvectumProxyRoutingService.exe'
$PackageToolFile = 'ArvectumDriverPackageTool.exe'
$BundleManifestName = 'native-stack-bundle.json'
$InstalledSchema = 'arvectum.proxy.windows-native-stack.v1'
$ProtocolVersion = 3
$StateRoot = Join-Path $env:ProgramData 'Arvectum\ProxyLauncher'
$InstalledMarker = Join-Path $StateRoot 'native-stack.json'
$LogPath = Join-Path $StateRoot 'native-stack-install.log'
$DriverStoreRoot = Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository'

function Is-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Log([string]$Message) {
    try {
        New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
        Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $Message" -Encoding utf8
    } catch {}
}

function Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Normalize-Path([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $text = [Environment]::ExpandEnvironmentVariables($Value.Trim().Trim('"'))
    if ($text.StartsWith('\??\')) { $text = $text.Substring(4) }
    if ($text.StartsWith('\SystemRoot\', [StringComparison]::OrdinalIgnoreCase)) {
        $text = Join-Path $env:SystemRoot $text.Substring(12)
    } elseif ($text.StartsWith('System32\', [StringComparison]::OrdinalIgnoreCase)) {
        $text = Join-Path $env:SystemRoot $text
    }
    try { return [IO.Path]::GetFullPath($text).TrimEnd('\').ToLowerInvariant() }
    catch { return $text.TrimEnd('\').ToLowerInvariant() }
}

function Get-ServiceRecord([string]$Name) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $path
    return [pscustomobject]@{
        Name = $Name
        ImagePath = [string]$item.ImagePath
        Type = [int]$item.Type
        Start = [int]$item.Start
    }
}

function Service-IsRunning([string]$Name) {
    try { return (Get-Service -Name $Name -ErrorAction Stop).Status -eq 'Running' }
    catch { return $false }
}

function Stop-ServiceBestEffort([string]$Name) {
    & sc.exe stop $Name 2>$null | Out-Null
    Start-Sleep -Milliseconds 400
}

function Delete-ServiceBestEffort([string]$Name) {
    & sc.exe delete $Name 2>$null | Out-Null
    Start-Sleep -Milliseconds 400
}

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing JSON file: $Path" }
    return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
}

function Signature-Evidence([string]$Path) {
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    return [pscustomobject]@{
        Status = $sig.Status.ToString()
        Subject = if ($sig.SignerCertificate) { [string]$sig.SignerCertificate.Subject } else { '' }
        Thumbprint = if ($sig.SignerCertificate) { [string]$sig.SignerCertificate.Thumbprint } else { '' }
    }
}

function Bundle-Path([string]$Root, [string]$Relative) {
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $full.StartsWith($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Bundle path escapes payload root: $Relative"
    }
    return $full
}

function Validate-Bundle([string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'PayloadRoot is required.' }
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
    $manifestPath = Join-Path $resolvedRoot $BundleManifestName
    $manifest = Read-Json $manifestPath
    if ([string]$manifest.schema -cne $InstalledSchema) { throw 'Native stack bundle schema mismatch.' }
    if ([int]$manifest.protocol_version -ne $ProtocolVersion) { throw 'Native stack protocol mismatch.' }
    $mode = [string]$manifest.signing_mode
    if ($mode -cne 'production' -and $mode -cne 'test') { throw 'Native stack signing_mode is invalid.' }
    if ($mode -eq 'test' -and -not $AllowTestBundle) { throw 'Test-signed native stack is forbidden by this installer.' }

    if ([string]$manifest.driver.filename -cne $DriverFile -or [string]$manifest.driver.service_name -cne $DriverService) {
        throw 'Native stack driver identity mismatch.'
    }
    if ([string]$manifest.service.filename -cne $ServiceFile -or [string]$manifest.service.service_name -cne $RoutingService) {
        throw 'Native stack routing service identity mismatch.'
    }
    if ([string]$manifest.package_tool.filename -cne $PackageToolFile) {
        throw 'Native stack driver package tool identity mismatch.'
    }
    if ([string]$manifest.driver.package.directory -cne '.') {
        throw 'Native stack driver package directory is invalid.'
    }
    if ([string]$manifest.driver.package.inf_filename -cne $DriverInf -or
        [string]$manifest.driver.package.catalog_filename -cne $DriverCatalog) {
        throw 'Native stack driver package metadata is invalid.'
    }

    $packageRoot = $resolvedRoot
    $driverPath = Bundle-Path $packageRoot $DriverFile
    $infPath = Bundle-Path $packageRoot $DriverInf
    $catalogPath = Bundle-Path $packageRoot $DriverCatalog
    $servicePath = Bundle-Path $resolvedRoot $ServiceFile
    $toolPath = Bundle-Path $resolvedRoot $PackageToolFile
    foreach ($required in @($driverPath,$infPath,$catalogPath,$servicePath,$toolPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Native stack payload file is missing: $required"
        }
    }

    if ((Hash $driverPath) -cne ([string]$manifest.driver.sha256).ToLowerInvariant()) { throw 'Native stack driver SHA256 mismatch.' }
    if ((Hash $infPath) -cne ([string]$manifest.driver.package.inf_sha256).ToLowerInvariant()) { throw 'Native stack INF SHA256 mismatch.' }
    if ((Hash $catalogPath) -cne ([string]$manifest.driver.package.catalog_sha256).ToLowerInvariant()) { throw 'Native stack catalog SHA256 mismatch.' }
    if ((Hash $servicePath) -cne ([string]$manifest.service.sha256).ToLowerInvariant()) { throw 'Native stack service SHA256 mismatch.' }
    if ((Hash $toolPath) -cne ([string]$manifest.package_tool.sha256).ToLowerInvariant()) { throw 'Native stack package tool SHA256 mismatch.' }

    if ($mode -eq 'production') {
        $catalogSig = Signature-Evidence $catalogPath
        if ($catalogSig.Status -cne 'Valid' -or $catalogSig.Subject -notmatch 'Microsoft Windows Hardware Compatibility Publisher') {
            throw 'Production driver catalog does not carry a valid Microsoft Hardware Compatibility signature.'
        }
        foreach ($item in @(
            [pscustomobject]@{ role='routing service'; path=$servicePath; expected=[string]$manifest.service.signature.subject },
            [pscustomobject]@{ role='driver package tool'; path=$toolPath; expected=[string]$manifest.package_tool.signature.subject }
        )) {
            $sig = Signature-Evidence $item.path
            if ($sig.Status -cne 'Valid') { throw "Production $($item.role) Authenticode signature is not valid." }
            if ([string]::IsNullOrWhiteSpace($item.expected) -or $sig.Subject -cne $item.expected) {
                throw "Production $($item.role) publisher mismatch."
            }
        }
    }
    return $manifest
}

function Installed-Marker {
    if (-not (Test-Path -LiteralPath $InstalledMarker -PathType Leaf)) { return $null }
    return Read-Json $InstalledMarker
}

function Assert-No-Foreign-Native-State($Marker) {
    $driver = Get-ServiceRecord $DriverService
    $service = Get-ServiceRecord $RoutingService
    if ($null -eq $Marker) {
        if ($driver -or $service -or (Test-Path -LiteralPath $InstallRoot)) {
            throw 'Native routing state exists without an Arvectum ownership marker; refusing mutation.'
        }
        return
    }
    if ((Normalize-Path ([string]$Marker.install_root)) -cne (Normalize-Path $InstallRoot)) {
        throw 'Installed native stack root does not match expected Arvectum root.'
    }
    if ($service) {
        $expectedService = Normalize-Path ([string]$Marker.service.image_path)
        if ((Normalize-Path $service.ImagePath) -cne $expectedService) {
            throw 'Refusing to modify foreign privileged routing service.'
        }
    }
    if ($driver) {
        $expectedDriver = Normalize-Path ([string]$Marker.driver.image_path)
        if ((Normalize-Path $driver.ImagePath) -cne $expectedDriver) {
            throw 'Refusing to modify foreign kernel routing service.'
        }
    }
}

function Invoke-PackageTool([string]$Tool, [string]$Operation, [string]$InfPath) {
    $token = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $env:TEMP "apl-driver-package-$token.out"
    $stderrPath = Join-Path $env:TEMP "apl-driver-package-$token.err"
    try {
        $p = Start-Process -FilePath $Tool -ArgumentList @($Operation,$InfPath) -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru -Wait
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue } else { '' }
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
            throw "Driver package $Operation failed with exit code $($p.ExitCode): $stderr"
        }
        return [pscustomobject]@{
            ExitCode = [int]$p.ExitCode
            RebootRequired = ($p.ExitCode -eq 3010 -or $stdout -match 'reboot=1')
            StdOut = [string]$stdout
        }
    } finally {
        Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Driver-RecordVerified($Bundle) {
    $record = Get-ServiceRecord $DriverService
    if ($null -eq $record) { throw 'Primitive driver package did not register its kernel service.' }
    if ($record.Type -ne 1 -or $record.Start -ne 3) { throw 'Primitive driver service type/start mode mismatch.' }
    $image = Normalize-Path $record.ImagePath
    $store = Normalize-Path $DriverStoreRoot
    if (-not ($image + '\').StartsWith($store + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Primitive driver image is not owned by Windows Driver Store.'
    }
    if (-not (Test-Path -LiteralPath $image -PathType Leaf)) { throw 'Primitive driver image is missing from Driver Store.' }
    if ((Hash $image) -cne [string]$Bundle.driver.sha256) { throw 'Driver Store image SHA256 mismatch.' }
    return [pscustomobject]@{ Record=$record; ImagePath=$image }
}

function Create-RoutingService([string]$ServicePath) {
    $existing = Get-ServiceRecord $RoutingService
    if ($existing) {
        Stop-ServiceBestEffort $RoutingService
        Delete-ServiceBestEffort $RoutingService
    }
    $dependency = "BFE/$DriverService"
    & sc.exe create $RoutingService type= own start= auto depend= $dependency binPath= $ServicePath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create privileged routing service.' }
}

function Start-And-VerifyNative($Bundle) {
    $servicePath = Join-Path $InstallRoot $ServiceFile
    Create-RoutingService $servicePath
    & sc.exe start $RoutingService | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to start privileged routing service and its driver dependency.' }
    if (-not (Service-IsRunning $DriverService) -or -not (Service-IsRunning $RoutingService)) {
        throw 'Native routing services did not reach RUNNING.'
    }
    $driverVerified = Driver-RecordVerified $Bundle
    $serviceRecord = Get-ServiceRecord $RoutingService
    if ($serviceRecord.Type -ne 16 -or $serviceRecord.Start -ne 2) { throw 'Privileged routing service type/start mode mismatch.' }
    if ((Normalize-Path $serviceRecord.ImagePath) -cne (Normalize-Path $servicePath)) { throw 'Privileged routing service path mismatch.' }
    return $driverVerified
}

function Write-InstalledMarker($Bundle, $DriverVerified) {
    New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
    $servicePath = Join-Path $InstallRoot $ServiceFile
    $payload = [ordered]@{
        schema = $InstalledSchema
        signing_mode = [string]$Bundle.signing_mode
        protocol_version = $ProtocolVersion
        installed_utc = [DateTime]::UtcNow.ToString('o')
        install_root = $InstallRoot
        source_commit = [string]$Bundle.source_commit
        version = [string]$Bundle.version
        driver = [ordered]@{
            filename = $DriverFile
            service_name = $DriverService
            sha256 = [string]$Bundle.driver.sha256
            image_path = [string]$DriverVerified.ImagePath
            package_inf_path = (Join-Path $InstallRoot $DriverInf)
            catalog_sha256 = [string]$Bundle.driver.package.catalog_sha256
        }
        service = [ordered]@{
            filename = $ServiceFile
            service_name = $RoutingService
            sha256 = [string]$Bundle.service.sha256
            image_path = $servicePath
        }
        package_tool = [ordered]@{
            filename = $PackageToolFile
            sha256 = [string]$Bundle.package_tool.sha256
        }
    }
    $tmp = "$InstalledMarker.tmp"
    $payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp -Encoding utf8
    Move-Item -LiteralPath $tmp -Destination $InstalledMarker -Force
}

function Native-StackHealthy($Marker) {
    if ($null -eq $Marker) { return $false }
    try {
        $driver = Get-ServiceRecord $DriverService
        $service = Get-ServiceRecord $RoutingService
        if ($null -eq $driver -or $null -eq $service) { return $false }
        if ($driver.Type -ne 1 -or $driver.Start -ne 3 -or $service.Type -ne 16 -or $service.Start -ne 2) { return $false }
        $driverPath = Normalize-Path $driver.ImagePath
        $servicePath = Normalize-Path $service.ImagePath
        if ($driverPath -cne (Normalize-Path ([string]$Marker.driver.image_path))) { return $false }
        if ($servicePath -cne (Normalize-Path ([string]$Marker.service.image_path))) { return $false }
        if ((Hash $driverPath) -cne [string]$Marker.driver.sha256) { return $false }
        if ((Hash $servicePath) -cne [string]$Marker.service.sha256) { return $false }
        return (Service-IsRunning $DriverService) -and (Service-IsRunning $RoutingService)
    } catch { return $false }
}

function Marker-MatchesBundle($Marker, $Bundle) {
    if ($null -eq $Marker) { return $false }
    return (
        [string]$Marker.schema -ceq $InstalledSchema -and
        [string]$Marker.signing_mode -ceq [string]$Bundle.signing_mode -and
        [int]$Marker.protocol_version -eq $ProtocolVersion -and
        [string]$Marker.driver.sha256 -ceq [string]$Bundle.driver.sha256 -and
        [string]$Marker.service.sha256 -ceq [string]$Bundle.service.sha256 -and
        [string]$Marker.package_tool.sha256 -ceq [string]$Bundle.package_tool.sha256
    )
}

function Restore-Previous([string]$OldRoot, $PreviousMarker) {
    Remove-Item -LiteralPath $InstalledMarker -Force -ErrorAction SilentlyContinue
    try {
        Stop-ServiceBestEffort $RoutingService
        Delete-ServiceBestEffort $RoutingService
        Stop-ServiceBestEffort $DriverService
        if (Test-Path -LiteralPath $InstallRoot) { Remove-Item -LiteralPath $InstallRoot -Recurse -Force }
        if ($PreviousMarker -and (Test-Path -LiteralPath $OldRoot -PathType Container)) {
            Move-Item -LiteralPath $OldRoot -Destination $InstallRoot
            $oldBundle = Validate-Bundle $InstallRoot
            $oldTool = Join-Path $InstallRoot $PackageToolFile
            $oldInf = Join-Path $InstallRoot $DriverInf
            $result = Invoke-PackageTool $oldTool 'install' $oldInf
            if ($result.RebootRequired) { throw 'previous driver package restore requires reboot' }
            $driverVerified = Start-And-VerifyNative $oldBundle
            Write-InstalledMarker $oldBundle $driverVerified
            Log 'previous native stack restored after failed update'
        } else {
            Remove-Item -LiteralPath $OldRoot -Recurse -Force -ErrorAction SilentlyContinue
            Log 'failed first native install cleaned up'
        }
    } catch {
        Remove-Item -LiteralPath $InstalledMarker -Force -ErrorAction SilentlyContinue
        Log "CRITICAL native stack rollback failure: $($_.Exception.Message)"
    }
}

function Install-Stack($Bundle, [string]$SourceRoot) {
    if (-not (Is-Administrator)) { throw 'Administrator privileges are required for native stack installation.' }
    $previous = Installed-Marker
    Assert-No-Foreign-Native-State $previous
    if ((Marker-MatchesBundle $previous $Bundle) -and (Native-StackHealthy $previous)) {
        Log 'native stack already exact and healthy; install is a no-op'
        return
    }

    $stageRoot = "$InstallRoot.new"
    $oldRoot = "$InstallRoot.old"
    Remove-Item -LiteralPath $stageRoot,$oldRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $SourceRoot '*') -Destination $stageRoot -Recurse -Force
    $stagedBundle = Validate-Bundle $stageRoot

    try {
        Stop-ServiceBestEffort $RoutingService
        Delete-ServiceBestEffort $RoutingService
        Stop-ServiceBestEffort $DriverService

        if (Test-Path -LiteralPath $InstallRoot -PathType Container) {
            Move-Item -LiteralPath $InstallRoot -Destination $oldRoot
        }
        Move-Item -LiteralPath $stageRoot -Destination $InstallRoot

        $tool = Join-Path $InstallRoot $PackageToolFile
        $inf = Join-Path $InstallRoot $DriverInf
        $packageResult = Invoke-PackageTool $tool 'install' $inf
        if ($packageResult.RebootRequired) { throw 'Driver package install requires reboot; update rolled back.' }

        $driverVerified = Start-And-VerifyNative $stagedBundle
        Write-InstalledMarker $stagedBundle $driverVerified
        Remove-Item -LiteralPath $oldRoot -Recurse -Force -ErrorAction SilentlyContinue
        Log "native stack install committed mode=$($stagedBundle.signing_mode)"
    } catch {
        $failure = $_
        try {
            if (Test-Path -LiteralPath $InstallRoot -PathType Container) {
                $currentTool = Join-Path $InstallRoot $PackageToolFile
                $currentInf = Join-Path $InstallRoot $DriverInf
                if ((Test-Path -LiteralPath $currentTool) -and (Test-Path -LiteralPath $currentInf)) {
                    Stop-ServiceBestEffort $RoutingService
                    Delete-ServiceBestEffort $RoutingService
                    Stop-ServiceBestEffort $DriverService
                    $removeResult = Invoke-PackageTool $currentTool 'uninstall' $currentInf
                    if ($removeResult.RebootRequired) { Log 'new driver package rollback requested reboot' }
                }
            }
        } catch { Log "new driver package cleanup failed: $($_.Exception.Message)" }
        Restore-Previous $oldRoot $previous
        throw $failure
    } finally {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Uninstall-Stack {
    if (-not (Is-Administrator)) { throw 'Administrator privileges are required for native stack uninstall.' }
    $marker = Installed-Marker
    if ($null -eq $marker) {
        Assert-No-Foreign-Native-State $null
        return
    }
    Assert-No-Foreign-Native-State $marker
    $bundle = Validate-Bundle $InstallRoot
    $tool = Join-Path $InstallRoot $PackageToolFile
    $inf = Join-Path $InstallRoot $DriverInf

    Stop-ServiceBestEffort $RoutingService
    Delete-ServiceBestEffort $RoutingService
    Stop-ServiceBestEffort $DriverService

    $result = Invoke-PackageTool $tool 'uninstall' $inf
    if ($result.RebootRequired) {
        throw 'Driver package uninstall requires reboot; application uninstall is blocked until cleanup can be completed safely.'
    }
    if (Get-ServiceRecord $DriverService) { throw 'Kernel routing service remains after primitive package uninstall.' }
    if (Get-ServiceRecord $RoutingService) { throw 'Privileged routing service remains after deletion.' }

    Remove-Item -LiteralPath $InstalledMarker -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
    Log "native stack uninstall committed mode=$($bundle.signing_mode)"
}

function Invoke-Elevated {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -InstallRoot "{2}" -Elevated' -f $PSCommandPath,$Action,$InstallRoot
    if ($PayloadRoot) { $arguments += (' -PayloadRoot "{0}"' -f $PayloadRoot) }
    if ($AllowTestBundle) { $arguments += ' -AllowTestBundle' }
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $process = Start-Process -FilePath $powershell -Verb RunAs -ArgumentList $arguments -PassThru -Wait
    exit $process.ExitCode
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows native-stack helper requires Windows.' }

    if ($Action -eq 'Status') {
        $marker = Installed-Marker
        if ($null -eq $marker) { Write-Output 'ARVECTUM_NATIVE_STACK_NOT_INSTALLED'; exit 1 }
        if (Native-StackHealthy $marker) { Write-Output "ARVECTUM_NATIVE_STACK_READY mode=$($marker.signing_mode)"; exit 0 }
        Write-Output "ARVECTUM_NATIVE_STACK_UNHEALTHY mode=$($marker.signing_mode)"
        exit 2
    }

    if ($Action -eq 'Preflight') {
        $bundle = Validate-Bundle $PayloadRoot
        Assert-No-Foreign-Native-State (Installed-Marker)
        Write-Output "ARVECTUM_NATIVE_STACK_PREFLIGHT_PASS mode=$($bundle.signing_mode)"
        exit 0
    }

    if (-not $Elevated -and -not (Is-Administrator)) { Invoke-Elevated }

    if ($Action -eq 'Install') {
        $bundle = Validate-Bundle $PayloadRoot
        Install-Stack $bundle ((Resolve-Path -LiteralPath $PayloadRoot).Path)
        Write-Output "ARVECTUM_NATIVE_STACK_INSTALL_PASS mode=$($bundle.signing_mode)"
        exit 0
    }
    if ($Action -eq 'Uninstall') {
        Uninstall-Stack
        Write-Output 'ARVECTUM_NATIVE_STACK_UNINSTALL_PASS'
        exit 0
    }
    throw "Unsupported action: $Action"
} catch {
    Log "native stack $Action failed: $($_.Exception.Message)"
    Write-Error $_.Exception.Message
    exit 1
}
