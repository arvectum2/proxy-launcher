[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ArtifactRoot = $Root
if (-not (Test-Path (Join-Path $ArtifactRoot 'WinDivert64.sys'))) {
    $ArtifactRoot = Split-Path -Parent $Root
}
$Helper = Join-Path $ArtifactRoot 'windivert_service_helper.ps1'
$Smoke = Join-Path $ArtifactRoot 'loopback_smoke.exe'
$BuildManifest = Join-Path $ArtifactRoot 'windivert-stack-build.json'
$ResultPath = Join-Path $ArtifactRoot 'service-acceptance.result'
$ServiceName = 'ArvectumProxyWinDivertRouting'
$MarkerPath = Join-Path $env:ProgramData 'Arvectum\ProxyLauncher\windivert-stack.json'
$InstallRoot = Join-Path $env:ProgramData 'Arvectum\ProxyLauncher\WinDivert'

Remove-Item $ResultPath -Force -ErrorAction SilentlyContinue

function Report {
    param([Parameter(Mandatory=$true)][string]$Line)
    Write-Output $Line
    Add-Content -LiteralPath $ResultPath -Value $Line -Encoding UTF8
}

function Assert-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $admin = [Security.Principal.WindowsBuiltInRole]::Administrator
    if (-not $principal.IsInRole($admin)) {
        throw 'service acceptance requires Administrator elevation'
    }
}

function Get-StringSha256 {
    param([Parameter(Mandatory=$true)][string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        $digest = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Read-Exact {
    param([Parameter(Mandatory=$true)]$Stream, [Parameter(Mandatory=$true)][int]$Length)
    $buffer = New-Object byte[] $Length
    $offset = 0
    while ($offset -lt $Length) {
        $read = $Stream.Read($buffer, $offset, $Length - $offset)
        if ($read -le 0) { throw 'named pipe returned a short frame' }
        $offset += $read
    }
    return $buffer
}

function Invoke-RoutingPipe {
    param([Parameter(Mandatory=$true)][string]$Json)
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'Arvectum.ProxyLauncher.WinDivertRouting', [System.IO.Pipes.PipeDirection]::InOut, [System.IO.Pipes.PipeOptions]::None)
    try {
        $pipe.Connect(5000)
        $payload = [Text.Encoding]::UTF8.GetBytes($Json)
        $header = [BitConverter]::GetBytes([uint32]$payload.Length)
        $pipe.Write($header, 0, $header.Length)
        $pipe.Write($payload, 0, $payload.Length)
        $pipe.Flush()
        $responseHeader = Read-Exact -Stream $pipe -Length 4
        $responseLength = [BitConverter]::ToUInt32($responseHeader, 0)
        if ($responseLength -le 0 -or $responseLength -gt 1048576) { throw 'named pipe response length is invalid' }
        $responseBody = Read-Exact -Stream $pipe -Length ([int]$responseLength)
        return [Text.Encoding]::UTF8.GetString($responseBody)
    } finally {
        $pipe.Dispose()
    }
}

function Stop-TestProcess {
    param($Process)
    if ($null -ne $Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
}

function Run-RoutingCase {
    param([Parameter(Mandatory=$true)][ValidateSet('ipv4','ipv6')][string]$Family, [Parameter(Mandatory=$true)][int]$ProxyPort, [Parameter(Mandatory=$true)][int]$DirectPort)
    $prefix = 'service-' + $Family
    foreach ($suffix in @('proxy.log','proxy.err','direct.log','direct.err','client.log','client.err')) {
        Remove-Item (Join-Path $ArtifactRoot ($prefix + '-' + $suffix)) -Force -ErrorAction SilentlyContinue
    }
    $proxy = $null
    $direct = $null
    try {
        $proxy = Start-Process -FilePath $Smoke -ArgumentList @('server',$ProxyPort,'PROXY',$Family) -RedirectStandardOutput (Join-Path $ArtifactRoot ($prefix + '-proxy.log')) -RedirectStandardError (Join-Path $ArtifactRoot ($prefix + '-proxy.err')) -PassThru
        $direct = Start-Process -FilePath $Smoke -ArgumentList @('server',$DirectPort,'DIRECT',$Family) -RedirectStandardOutput (Join-Path $ArtifactRoot ($prefix + '-direct.log')) -RedirectStandardError (Join-Path $ArtifactRoot ($prefix + '-direct.err')) -PassThru
        Start-Sleep -Milliseconds 500
        $normalized = [IO.Path]::GetFullPath($Smoke).Replace('/', '\').ToLowerInvariant()
        $applicationHash = Get-StringSha256 -Value $normalized
        $ruleId = 'acceptance.' + $Family
        $canonicalPlan = '{"applications":[{"application_path_sha256":"' + $applicationHash + '","local_proxy_port":' + $ProxyPort + ',"rule_id":"' + $ruleId + '"}],"backend":"windivert","protocol_version":1}'
        $planDigest = Get-StringSha256 -Value $canonicalPlan
        $sessionId = [guid]::NewGuid().ToString().ToLowerInvariant()
        $apply = '{"applications":[{"application_path_sha256":"' + $applicationHash + '","local_proxy_port":' + $ProxyPort + ',"rule_id":"' + $ruleId + '"}],"command":"apply_plan","owned_resources":["Arvectum.ProxyLauncher.WinDivert.SocketTracker","Arvectum.ProxyLauncher.WinDivert.NetworkTranslator"],"plan_digest":"' + $planDigest + '","protocol_version":1,"proxy":{"direct_listener_port":' + $DirectPort + ',"pid":' + $proxy.Id + '},"session_id":"' + $sessionId + '"}'
        $applyText = Invoke-RoutingPipe -Json $apply
        $applyResponse = $applyText | ConvertFrom-Json
        if ([string]$applyResponse.status -cne 'ok' -or [string]$applyResponse.command -cne 'apply_plan' -or @($applyResponse.applied_resources).Count -ne 2) { throw ('service apply failed: ' + $applyText) }
        Report ('ARVECTUM_WINDIVERT_SERVICE_APPLY PASS family=' + $Family)
        $client = Start-Process -FilePath $Smoke -ArgumentList @('client',$ProxyPort,$Family) -RedirectStandardOutput (Join-Path $ArtifactRoot ($prefix + '-client.log')) -RedirectStandardError (Join-Path $ArtifactRoot ($prefix + '-client.err')) -Wait -PassThru
        $clientText = Get-Content (Join-Path $ArtifactRoot ($prefix + '-client.log')) -Raw
        if ($clientText -notmatch 'CLIENT_RESULT=DIRECT') { throw ('service-selected ' + $Family + ' client did not reach DIRECT listener') }
        Report ('ARVECTUM_WINDIVERT_SERVICE_ROUTE PASS family=' + $Family + ' result=DIRECT')
        $restore = '{"command":"restore","owned_resources":["Arvectum.ProxyLauncher.WinDivert.SocketTracker","Arvectum.ProxyLauncher.WinDivert.NetworkTranslator"],"plan_digest":"' + $planDigest + '","protocol_version":1,"session_id":"' + $sessionId + '"}'
        $restoreText = Invoke-RoutingPipe -Json $restore
        $restoreResponse = $restoreText | ConvertFrom-Json
        if ([string]$restoreResponse.status -cne 'ok' -or [string]$restoreResponse.command -cne 'restore' -or @($restoreResponse.removed_resources).Count -ne 2 -or @($restoreResponse.remaining_owned_resources).Count -ne 0) { throw ('service restore failed: ' + $restoreText) }
        Report ('ARVECTUM_WINDIVERT_SERVICE_RESTORE PASS family=' + $Family + ' removed=2 remaining=0')
    } finally {
        Stop-TestProcess $direct
        Stop-TestProcess $proxy
    }
}

Assert-Elevated
if (-not (Test-Path -LiteralPath $BuildManifest -PathType Leaf)) { throw 'windivert stack build manifest is absent' }
$build = Get-Content -LiteralPath $BuildManifest -Raw | ConvertFrom-Json
$sourceCommit = [string]$build.source_commit
if ($sourceCommit -notmatch '^[0-9a-f]{40}$') { throw 'windivert stack source commit is invalid' }

$failure = $null
try {
    try { & $Helper -Action Uninstall | Out-Null } catch {}
    & $Helper -Action Install -SourceDirectory $ArtifactRoot -SourceCommit $sourceCommit | Out-Null
    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($service.Status -ne [ServiceProcess.ServiceControllerStatus]::Running) { throw 'routing service is not running' }
    if (-not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) { throw 'routing stack marker is absent' }
    $marker = Get-Content -LiteralPath $MarkerPath -Raw | ConvertFrom-Json
    if ([string]$marker.source_commit -cne $sourceCommit) { throw 'routing stack source commit mismatch' }
    Report ('ARVECTUM_WINDIVERT_SERVICE_INSTALL PASS commit=' + $sourceCommit)
    Run-RoutingCase -Family 'ipv4' -ProxyPort 38180 -DirectPort 38181
    Run-RoutingCase -Family 'ipv6' -ProxyPort 38182 -DirectPort 38183
} catch {
    $failure = $_
    Report ('ARVECTUM_WINDIVERT_SERVICE_ACCEPTANCE FAIL error=' + $_.Exception.Message)
} finally {
    try { & $Helper -Action Uninstall | Out-Null } catch {
        if ($null -eq $failure) { $failure = $_ }
        Report ('ARVECTUM_WINDIVERT_SERVICE_CLEANUP FAIL error=' + $_.Exception.Message)
    }
}

$serviceAfter = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$markerAfter = Test-Path -LiteralPath $MarkerPath
$filesAfter = Test-Path -LiteralPath $InstallRoot
if ($null -ne $serviceAfter -or $markerAfter -or $filesAfter) {
    if ($null -eq $failure) { $failure = [RuntimeException]::new('service cleanup is incomplete') }
    Report 'ARVECTUM_WINDIVERT_SERVICE_CLEANUP FAIL residual_state=true'
} else {
    Report 'ARVECTUM_WINDIVERT_SERVICE_CLEANUP PASS service=absent files=absent marker=absent'
}

if ($null -ne $failure) { throw $failure }
Report 'ARVECTUM_WINDIVERT_SERVICE_ACCEPTANCE PASS families=ipv4,ipv6'
