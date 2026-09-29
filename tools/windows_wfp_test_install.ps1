param(
    [Parameter(Mandatory=$true)][string]$DriverPath,
    [Parameter(Mandatory=$true)][string]$CertificatePath,
    [switch]$EnableTestSigning
)

$ErrorActionPreference = 'Stop'
$serviceName = 'ArvectumProxyRoutingCallout'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required.'
    }
}

function Test-TestSigningEnabled {
    $text = (& bcdedit.exe /enum '{current}' | Out-String)
    return ($text -match '(?im)^testsigning\s+Yes\s*$')
}

Assert-Administrator
$DriverPath = (Resolve-Path $DriverPath).Path
$CertificatePath = (Resolve-Path $CertificatePath).Path

if (-not (Test-TestSigningEnabled)) {
    if (-not $EnableTestSigning) {
        throw 'Windows test signing is disabled. Re-run with -EnableTestSigning, then reboot.'
    }
    & bcdedit.exe /set testsigning on | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to enable Windows test signing.'
    }
    Write-Output 'ARVECTUM_WFP_REBOOT_REQUIRED'
    exit 3010
}

$cert = Import-Certificate -FilePath $CertificatePath -CertStoreLocation 'Cert:\LocalMachine\Root'
Import-Certificate -FilePath $CertificatePath -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null

& sc.exe stop $serviceName 2>$null | Out-Null
& sc.exe delete $serviceName 2>$null | Out-Null
Start-Sleep -Milliseconds 500

& sc.exe create $serviceName type= kernel start= demand binPath= $DriverPath | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to create kernel service.'
}
& sc.exe start $serviceName | Out-Host
if ($LASTEXITCODE -ne 0) {
    & sc.exe delete $serviceName | Out-Null
    throw 'Failed to start WFP callout driver.'
}

$state = & sc.exe query $serviceName | Out-String
if ($state -notmatch 'STATE\s+:\s+4\s+RUNNING') {
    throw 'WFP callout driver did not reach RUNNING state.'
}
Write-Output ('ARVECTUM_WFP_DRIVER_READY thumbprint=' + $cert.Thumbprint)
