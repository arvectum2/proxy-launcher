[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Smoke = Join-Path $Root "loopback_smoke.exe"
$ProbeBatch = Join-Path $Root "windivert_nat_probe_run.cmd"
$ProxyPort = 38180
$DirectPort = 38181

function Start-SmokeServer {
    param([int]$Port, [string]$Marker, [string]$LogName)
    $Arguments = @("server", $Port, $Marker)
    $Stdout = Join-Path $Root ($LogName + ".log")
    $Stderr = Join-Path $Root ($LogName + ".err")
    return Start-Process -FilePath $Smoke -ArgumentList $Arguments -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru
}

function Run-SmokeClient {
    param([int]$Port, [string]$LogName)
    $Arguments = @("client", $Port)
    $Stdout = Join-Path $Root ($LogName + ".log")
    $Stderr = Join-Path $Root ($LogName + ".err")
    return Start-Process -FilePath $Smoke -ArgumentList $Arguments -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -Wait -PassThru
}

function Stop-SmokeServer {
    param($Process)
    if ($null -ne $Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
}

$Logs = @(
    "baseline-proxy.log", "baseline-proxy.err",
    "baseline-client.log", "baseline-client.err",
    "live-proxy.log", "live-proxy.err",
    "live-direct.log", "live-direct.err",
    "live-client.log", "live-client.err",
    "probe.log", "probe.err"
)
foreach ($Name in $Logs) {
    Remove-Item (Join-Path $Root $Name) -Force -ErrorAction SilentlyContinue
}

$BaselineServer = $null
$ProxyServer = $null
$DirectServer = $null
try {
    $BaselineServer = Start-SmokeServer -Port $ProxyPort -Marker "PROXY" -LogName "baseline-proxy"
    Start-Sleep -Milliseconds 400
    $BaselineClient = Run-SmokeClient -Port $ProxyPort -LogName "baseline-client"
    [void]$BaselineServer.WaitForExit(3000)
    $BaselineText = Get-Content (Join-Path $Root "baseline-client.log") -Raw
    if ($BaselineText -notmatch "CLIENT_RESULT=PROXY") {
        throw "Baseline did not reach the normal proxy listener."
    }
    Write-Output "ARVECTUM_WINDIVERT_BASELINE PASS result=PROXY"

    $ProxyServer = Start-SmokeServer -Port $ProxyPort -Marker "PROXY" -LogName "live-proxy"
    $DirectServer = Start-SmokeServer -Port $DirectPort -Marker "DIRECT" -LogName "live-direct"
    Start-Sleep -Milliseconds 400

    Write-Output "ARVECTUM_WINDIVERT_UAC_REQUEST"
    $ProbeProcess = Start-Process -FilePath $ProbeBatch -Verb RunAs -PassThru

    $Ready = $false
    $ReadyDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $ReadyDeadline) {
        $ProbeLog = Join-Path $Root "probe.log"
        if (Test-Path $ProbeLog) {
            $ProbeText = Get-Content $ProbeLog -Raw
            if ($ProbeText -match "READY proxy_port=") {
                $Ready = $true
                break
            }
        }
        Start-Sleep -Milliseconds 200
    }
    if (-not $Ready) {
        throw "Elevated WinDivert probe did not become ready."
    }

    $LiveClient = Run-SmokeClient -Port $ProxyPort -LogName "live-client"
    $LiveText = Get-Content (Join-Path $Root "live-client.log") -Raw
    if ($LiveText -notmatch "CLIENT_RESULT=DIRECT") {
        throw "Selected client did not reach the direct listener."
    }

    if (-not $ProbeProcess.WaitForExit(20000)) {
        throw "WinDivert probe did not exit after its bounded test window."
    }
    $ProbeText = Get-Content (Join-Path $Root "probe.log") -Raw
    $ResultPattern = "RESULT selected_connects=(\d+) redirected_outbound=(\d+) rewritten_return=(\d+) unmatched_proxy_packets=(\d+)"
    $Match = [regex]::Match($ProbeText, $ResultPattern)
    if (-not $Match.Success) {
        throw "WinDivert probe did not emit a parseable result."
    }
    $Selected = [int]$Match.Groups[1].Value
    $Redirected = [int]$Match.Groups[2].Value
    $Returned = [int]$Match.Groups[3].Value
    $Missed = [int]$Match.Groups[4].Value
    if ($Selected -lt 1 -or $Redirected -lt 1 -or $Returned -lt 1) {
        throw "WinDivert probe counters do not prove bidirectional NAT."
    }
    if ($Missed -ne 0) {
        throw "WinDivert SOCKET-to-NETWORK correlation race detected."
    }

    Write-Output ("ARVECTUM_WINDIVERT_ACCEPTANCE PASS selected={0} redirected={1} returned={2} missed={3}" -f $Selected, $Redirected, $Returned, $Missed)
}
finally {
    Stop-SmokeServer $BaselineServer
    Stop-SmokeServer $ProxyServer
    Stop-SmokeServer $DirectServer
}
