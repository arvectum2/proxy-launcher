[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$PayloadRoot,
  [Parameter(Mandatory)] [string]$InstallRoot,
  [string]$LegacyInstallRoot,
  [switch]$PreflightOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$StateRoot = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
$LogPath = Join-Path $StateRoot 'install.log'
$RunPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RecoveryRunName = 'ArvectumProxyLauncherRecovery'
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

function Write-InstallLog([string]$Message) {
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $Message" -Encoding utf8
}

function Get-Sha256([string]$Path) {
  $CertUtil = Join-Path $env:SystemRoot 'System32\certutil.exe'
  if (-not (Test-Path -LiteralPath $CertUtil -PathType Leaf)) { throw 'certutil.exe not found in System32' }
  $output = & $CertUtil -hashfile $Path SHA256
  if ($LASTEXITCODE -ne 0) { throw "certutil SHA256 failed for $Path" }
  $hash = @()
  foreach ($line in $output) {
    $stripped = $line -replace '^\s+|\s+$'
    if ($stripped -match '^[0-9A-Fa-f]{64}$') { $hash += $stripped }
  }
  if ($hash.Count -eq 0) { throw "certutil SHA256 produced no hash candidate for $Path" }
  if ($hash.Count -gt 1) { throw "certutil SHA256 produced multiple hash candidates for $Path" }
  return $hash[0]
}

function Test-ExactPath([string]$Candidate, [string]$Expected) {
  if (-not $Candidate -or -not $Expected) { return $false }
  try {
    $resolvedCandidate = (Resolve-Path -LiteralPath $Candidate -ErrorAction Stop).Path -replace '\\+$'
  } catch {
    Write-InstallLog "Test-ExactPath RESOLVE_FAILED Candidate='$Candidate'"
    return $false
  }
  try {
    $resolvedExpected = (Resolve-Path -LiteralPath $Expected -ErrorAction Stop).Path -replace '\\+$'
  } catch {
    Write-InstallLog "Test-ExactPath RESOLVE_FAILED Expected='$Expected'"
    return $false
  }
  $result = $resolvedCandidate -ieq $resolvedExpected
  Write-InstallLog "Test-ExactPath Candidate='$Candidate' Expected='$Expected' ResolvedCandidate='$resolvedCandidate' ResolvedExpected='$resolvedExpected' Match=$result"
  return $result
}

function Get-RecoveryBackups {
  @('proxy_internet_backup.json','proxy_env_backup.json') |
    ForEach-Object { Join-Path $StateRoot $_ } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
}

function Get-OwnedProcesses([string]$Exe) {
  if (-not $Exe -or -not (Test-Path -LiteralPath $Exe -PathType Leaf)) { return @() }
  @(Get-CimInstance Win32_Process -Filter "Name='Arvectum Proxy Launcher.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -and (Test-ExactPath $_.ExecutablePath $Exe) })
}

function Stop-OwnedProcess([string]$Exe) {
  foreach ($process in @(Get-OwnedProcesses $Exe)) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
  }
}

function Test-OwnedStartCommand([string]$Command, [string]$ExpectedExe) {
  if (-not $Command -or -not $ExpectedExe) { return $false }
  if ($Command -notmatch '^\s*"([^"]+)"\s+--start\s*$') { return $false }
  return Test-ExactPath $matches[1] $ExpectedExe
}

function Get-RunValue([string]$Name) {
  try {
    $item = Get-ItemProperty -Path $RunPath -ErrorAction Stop
  } catch [System.Management.Automation.ItemNotFoundException] {
    return $null
  }
  $property = $item.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return [string]$property.Value
}

function Remove-StaleRecoveryRun([string]$ExpectedExe) {
  if (@(Get-RecoveryBackups).Count -ne 0) { return }
  $value = Get-RunValue $RecoveryRunName
  if (-not $value) { return }
  if ($ExpectedExe -and (Test-OwnedStartCommand $value $ExpectedExe)) {
    Remove-ItemProperty -Path $RunPath -Name $RecoveryRunName -ErrorAction Stop
    Write-InstallLog 'stale owned recovery Run value removed'
  }
}

function Assert-PreflightRecoverySafe([string]$PreviousExe) {
  $backups = @(Get-RecoveryBackups)
  if ($backups.Count -ne 0 -and (-not $PreviousExe -or -not (Test-Path -LiteralPath $PreviousExe -PathType Leaf))) {
    throw 'recovery backups remain but the installed Launcher executable is missing; repair is blocked until network recovery can be proven'
  }
  $recovery = Get-RunValue $RecoveryRunName
  if ($recovery) {
    if (-not $PreviousExe -or -not (Test-OwnedStartCommand $recovery $PreviousExe)) {
      throw 'conflicting recovery autostart is not owned'
    }
  }
}

function Assert-RecoverySafe([string]$ExpectedExe) {
  $backups = @(Get-RecoveryBackups)
  if ($backups.Count -ne 0) { throw 'recovery backups remain after stopping the previous version' }
  $recovery = Get-RunValue $RecoveryRunName
  if ($recovery -and (-not $ExpectedExe -or -not (Test-OwnedStartCommand $recovery $ExpectedExe))) {
    throw 'conflicting recovery autostart is not owned'
  }
}

function Remove-StalePid([string]$ExpectedExe) {
  $pidPath = Join-Path $StateRoot 'proxy_core.pid'
  if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) { return }
  $raw = (Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue) -replace '^\s+|\s+$'
  $parsedPid = 0
  $validPid = $false
  if ($raw -match '^\d+$') {
    try { $parsedPid = [int]$Matches[0]; $validPid = $true } catch { $validPid = $false }
  } else {
    try {
      $record = $raw | ConvertFrom-Json
      $parsedPid = [int]$record.pid
      $validPid = $parsedPid -gt 0
    } catch { $validPid = $false }
  }
  $process = $null
  if ($validPid -and $parsedPid -gt 0) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$parsedPid" -ErrorAction SilentlyContinue
  }
  if (-not $process -or -not $process.ExecutablePath -or -not $ExpectedExe -or -not (Test-ExactPath $process.ExecutablePath $ExpectedExe)) {
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction Stop
    Write-InstallLog 'stale runtime PID removed'
  }
}

function Clear-StaleMaintenanceState([string]$ExpectedExe) {
  if (@(Get-RecoveryBackups).Count -ne 0) {
    throw 'refusing stale-state cleanup while recovery backups exist'
  }
  Remove-StaleRecoveryRun $ExpectedExe
  Remove-StalePid $ExpectedExe
  foreach ($suffix in @('.new','.old')) {
    $candidate = "$ExpectedExe$suffix"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      Remove-Item -LiteralPath $candidate -Force -ErrorAction Stop
      Write-InstallLog "stale transactional artifact removed: $suffix"
    }
  }
}

function Invoke-PreviousRollback([string]$ExistingExe) {
  $backups = @(Get-RecoveryBackups)
  if ($backups.Count -gt 0) {
    if (-not $ExistingExe -or -not (Test-Path -LiteralPath $ExistingExe -PathType Leaf)) {
      throw 'recovery backups remain but the installed Launcher executable is missing; repair is blocked until network recovery can be proven'
    }
    Write-InstallLog 'waiting for previous-version network rollback'
    $rollback = Start-Process -FilePath $ExistingExe -ArgumentList '--stop' -Wait -PassThru
    if ($rollback.ExitCode -ne 0) { throw 'previous version did not complete network rollback' }
    if (@(Get-RecoveryBackups).Count -gt 0) { throw 'recovery backups remain after previous-version rollback' }
    Write-InstallLog 'previous-version network rollback completed'
  }
  if ($ExistingExe) { Stop-OwnedProcess $ExistingExe }
}

function Get-PreviousInstallRoot {
  $candidates = @($InstallRoot)
  if ($LegacyInstallRoot) { $candidates += $LegacyInstallRoot }
  $seen = @{}
  foreach ($root in $candidates) {
    if (-not $root) { continue }
    $key = $root -replace '\\+$',''
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $exe = Join-Path $root 'Arvectum Proxy Launcher.exe'
    $marker = Join-Path $root '.arvectum-install-owner'
    if ((Test-Path -LiteralPath $exe -PathType Leaf) -or (Test-Path -LiteralPath $marker -PathType Leaf)) {
      return $root
    }
  }
  return $null
}

function Get-MaintenanceKind([string]$ExistingRoot, [string]$ExistingExe, [string]$OwnerMarker, $IncomingManifest) {
  if (-not $ExistingRoot -or (-not (Test-Path -LiteralPath $ExistingExe -PathType Leaf) -and -not (Test-Path -LiteralPath $OwnerMarker -PathType Leaf))) {
    return 'INSTALL'
  }
  $installedManifestPath = Join-Path $ExistingRoot 'build_manifest.json'
  if (Test-Path -LiteralPath $installedManifestPath -PathType Leaf) {
    try {
      $installedManifest = Get-Content -LiteralPath $installedManifestPath -Raw | ConvertFrom-Json
      $installedVersion = [string]$installedManifest.version
      $incomingVersion = [string]$IncomingManifest.version
      if ($installedVersion -and $incomingVersion -and $installedVersion -ne $incomingVersion) {
        return 'UPGRADE'
      }
    } catch {
      Write-InstallLog "installed manifest could not be classified: $($_.Exception.Message)"
    }
  }
  return 'REPAIR'
}

function Start-RuntimeAndVerify([string]$Exe, [string]$Label) {
  if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "$Label executable is missing" }
  $working = Split-Path -Parent $Exe
  $process = Start-Process -FilePath $Exe -ArgumentList '--start' -WorkingDirectory $working -PassThru
  Start-Sleep -Milliseconds 2000
  $process.Refresh()
  if ($process.HasExited) {
    throw "$Label runtime exited during restart with code $($process.ExitCode)"
  }
  Write-InstallLog "$Label runtime restart verified alive; PID=$($process.Id)"
}

function Stop-TargetRuntimeBestEffort([string]$Exe) {
  try {
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { return }
    if (@(Get-RecoveryBackups).Count -gt 0) {
      $stop = Start-Process -FilePath $Exe -ArgumentList '--stop' -Wait -PassThru
      Write-InstallLog "failed-handover target --stop exit code: $($stop.ExitCode)"
    }
    Stop-OwnedProcess $Exe
  } catch {
    Write-InstallLog "failed-handover target stop error: $($_.Exception.Message)"
  }
}

try {
  Write-InstallLog '=== INSTALL SESSION START'
  Write-InstallLog "PayloadRoot: $PayloadRoot"
  Write-InstallLog "InstallRoot: $InstallRoot"
  Write-InstallLog "LegacyInstallRoot: $LegacyInstallRoot"
  $manifest = Get-Content -LiteralPath (Join-Path $PayloadRoot 'build_manifest.json') -Raw | ConvertFrom-Json
  $payloadExe = Join-Path $PayloadRoot 'Arvectum Proxy Launcher.exe'
  Write-InstallLog "payload EXE: $payloadExe"
  $embeddedHash = Get-Sha256 $payloadExe
  Write-InstallLog "embedded application expected SHA256: $($manifest.application_sha256)"
  if ($embeddedHash -ine $manifest.application_sha256) { throw 'embedded application SHA256 verification failed' }
  $selfHash = Get-Sha256 (Join-Path $PayloadRoot 'upgrade_helper.ps1')
  if ($selfHash -ine $manifest.upgrade_helper_sha256) { throw 'upgrade helper SHA256 verification failed' }

  $previousRoot = Get-PreviousInstallRoot
  $previousExe = $null
  $ownerMarker = $null
  if ($previousRoot) {
    $previousExe = Join-Path $previousRoot 'Arvectum Proxy Launcher.exe'
    $ownerMarker = Join-Path $previousRoot '.arvectum-install-owner'
  }
  $targetExe = Join-Path $InstallRoot 'Arvectum Proxy Launcher.exe'
  $maintenanceKind = Get-MaintenanceKind $previousRoot $previousExe $ownerMarker $manifest
  Write-InstallLog "maintenance mode: $maintenanceKind"
  Write-InstallLog "incoming version: $($manifest.version)"
  Write-InstallLog "previous root: $previousRoot"
  Write-InstallLog "previous EXE: $previousExe"
  Write-InstallLog "final EXE: $targetExe"

  # Preflight is intentionally observational. No --stop, process kill, Run-value
  # deletion, PID cleanup or installation-root mutation may occur before this exit.
  Assert-PreflightRecoverySafe $previousExe
  if ($PreflightOnly) {
    Write-InstallLog "=== INSTALL SESSION END: PASS (read-only preflight $maintenanceKind)"
    exit 0
  }

  # Stage and hash-verify the incoming binary before touching the live runtime.
  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
  $staged = "$targetExe.installing"
  $old = "$targetExe.old"
  Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
  Copy-Item -LiteralPath $payloadExe -Destination $staged -Force
  if ((Get-Sha256 $staged) -ine $manifest.application_sha256) { throw 'staged application SHA256 verification failed' }
  Write-InstallLog 'incoming application staged and verified before runtime handover'

  $previousRuntimeActive = @(Get-RecoveryBackups).Count -gt 0
  $targetExistedBefore = Test-Path -LiteralPath $targetExe -PathType Leaf
  $handoverStarted = $false

  try {
    $handoverStarted = $true
    Invoke-PreviousRollback $previousExe
    Remove-StaleRecoveryRun $previousExe
    Assert-RecoverySafe $previousExe
    Clear-StaleMaintenanceState $targetExe

    if (Test-Path -LiteralPath $old -PathType Leaf) { Remove-Item -LiteralPath $old -Force }
    if ($targetExistedBefore -and (Test-Path -LiteralPath $targetExe -PathType Leaf)) {
      Move-Item -LiteralPath $targetExe -Destination $old -Force
    }
    Move-Item -LiteralPath $staged -Destination $targetExe -Force
    if ((Get-Sha256 $targetExe) -ine $manifest.application_sha256) { throw 'final application SHA256 verification failed' }

    if ($previousRuntimeActive) {
      Start-RuntimeAndVerify $targetExe 'new-version'
    }

    if (Test-Path -LiteralPath $old -PathType Leaf) { Remove-Item -LiteralPath $old -Force }
    Write-InstallLog 'transactional runtime handover committed'
  } catch {
    $handoverError = $_
    Write-InstallLog "transactional handover failure: $($handoverError.Exception.Message)"
    Stop-TargetRuntimeBestEffort $targetExe

    try {
      if (Test-Path -LiteralPath $targetExe -PathType Leaf) {
        Remove-Item -LiteralPath $targetExe -Force -ErrorAction Stop
      }
      if ($targetExistedBefore -and (Test-Path -LiteralPath $old -PathType Leaf)) {
        Move-Item -LiteralPath $old -Destination $targetExe -Force
      }
      if (Test-Path -LiteralPath $staged -PathType Leaf) {
        Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
      }
      Write-InstallLog 'transactional replacement rolled back'
    } catch {
      Write-InstallLog "application rollback error: $($_.Exception.Message)"
    }

    if ($handoverStarted -and $previousRuntimeActive -and $previousExe -and (Test-Path -LiteralPath $previousExe -PathType Leaf)) {
      try {
        Start-RuntimeAndVerify $previousExe 'previous-version recovery'
        Write-InstallLog 'previous runtime restored after failed handover'
      } catch {
        Write-InstallLog "CRITICAL: previous runtime restart failed after handover failure: $($_.Exception.Message)"
      }
    }
    throw $handoverError
  }

  Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
  $releaseFolder = 'arvectum-proxy-launcher-windows'
  Write-InstallLog "=== INSTALL SESSION END: PASS ($maintenanceKind)"
} catch {
  Write-InstallLog "ERROR TYPE: $($_.Exception.GetType().Name)"
  Write-InstallLog "ERROR MESSAGE: $($_.Exception.Message)"
  exit 1
}
