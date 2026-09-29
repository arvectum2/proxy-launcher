param(
    [Parameter(Mandatory=$true)][string]$AcceptanceExe,
    [string]$TargetUrl = 'http://example.com',
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator privileges are required.'
}

$AcceptanceExe = (Resolve-Path $AcceptanceExe).Path
$selectedSource = Join-Path (Split-Path -Parent $AcceptanceExe) 'ArvectumWfpSelectedClient.exe'
if (-not (Test-Path $selectedSource)) { throw 'ArvectumWfpSelectedClient.exe is missing from the acceptance bundle.' }
$targetUri = [Uri]$TargetUrl
if ($targetUri.Scheme -ne 'http') { throw 'Deterministic selected-client acceptance requires an http:// target.' }
$targetPort = if ($targetUri.IsDefaultPort) { 80 } else { $targetUri.Port }
$targetAddress = [System.Net.Dns]::GetHostAddresses($targetUri.DnsSafeHost) | Where-Object AddressFamily -eq ([System.Net.Sockets.AddressFamily]::InterNetwork) | Select-Object -First 1
if (-not $targetAddress) { throw ('No IPv4 address resolved for ' + $targetUri.DnsSafeHost) }
$targetIp = $targetAddress.IPAddressToString

$work = Join-Path $env:TEMP 'apl-wfp-live'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$selected = Join-Path $work 'selected-wfp-client.exe'
$stdout = Join-Path $work 'acceptance.stdout.txt'
$stderr = Join-Path $work 'acceptance.stderr.txt'
Copy-Item $selectedSource $selected -Force
Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
$process = Start-Process -FilePath $AcceptanceExe -ArgumentList @('--self-relay', ('"' + $selected + '"'), [string]$TimeoutSeconds) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

$deadline = (Get-Date).AddSeconds(15)
$ready = $false
while ((Get-Date) -lt $deadline -and -not $process.HasExited) {
    Start-Sleep -Milliseconds 200
    if (Test-Path $stdout) {
        $text = Get-Content $stdout -Raw -ErrorAction SilentlyContinue
        if ($text -match 'ARVECTUM_WFP_SELF_RELAY_READY') { $ready = $true; break }
    }
}
if (-not $ready) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    throw ('Acceptance helper did not become ready. ' + (Get-Content $stderr -Raw -ErrorAction SilentlyContinue))
}

$unselected = & "$env:WINDIR\System32\curl.exe" -4 -sS --max-time 20 -o NUL -w '%{http_code}' $TargetUrl
if ($LASTEXITCODE -ne 0 -or $unselected -ne '200') {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    throw ('Unselected curl baseline failed: exit=' + $LASTEXITCODE + ' http=' + $unselected)
}
Start-Sleep -Milliseconds 500
if ($process.HasExited) { throw 'Unselected executable unexpectedly matched the selected-app WFP filter.' }

$selectedOutput = & $selected $targetIp ([string]$targetPort) $targetUri.DnsSafeHost
$selectedExit = $LASTEXITCODE
$selectedResult = if ($selectedOutput -match 'ARVECTUM_WFP_SELECTED_CLIENT_HTTP_200') { '200' } else { '000' }
if (-not $process.HasExited) { Wait-Process -Id $process.Id -Timeout ($TimeoutSeconds + 10) }
$process.WaitForExit()
$process.Refresh()
$helperExit = $process.ExitCode

$log = Get-Content $stdout -Raw -ErrorAction SilentlyContinue
$err = Get-Content $stderr -Raw -ErrorAction SilentlyContinue
if ($selectedExit -ne 0 -or $selectedResult -ne '200') {
    throw ('Selected client failed through WFP relay: exit=' + $selectedExit + ' http=' + $selectedResult + ' client=' + $selectedOutput + ' stdout=' + $log + ' stderr=' + $err)
}
if ($null -ne $helperExit -and $helperExit -ne 0) {
    throw ('Acceptance helper failed with exit code ' + $helperExit + ': stdout=' + $log + ' stderr=' + $err)
}
if ($log -notmatch 'ARVECTUM_WFP_REDIRECT_OBSERVED') { throw 'No WFP redirect observation was recorded for the selected executable.' }
if ($log -match 'ARVECTUM_WFP_REDIRECT_OBSERVED original=(127\.|::1:)') { throw ('WFP redirect context still reports a loopback original destination: ' + $log) }
if ($log -notmatch 'ARVECTUM_WFP_SELF_RELAY_RESTORED') { throw 'Acceptance helper did not confirm restoration.' }

Write-Output 'ARVECTUM_WFP_LIVE_ACCEPTANCE_PASS'
Write-Output ('unselected_http=' + $unselected)
Write-Output ('selected_http=' + $selectedResult)
Write-Output ('selected_target=' + $targetIp + ':' + $targetPort)
Write-Output $log.Trim()