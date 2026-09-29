param(
    [Parameter(Mandatory=$true)][string]$DriverPath,
    [Parameter(Mandatory=$true)][string]$CertificatePath,
    [switch]$EnableTestSigning
)

$ErrorActionPreference = 'Stop'
$serviceName = 'ArvectumProxyRoutingCallout'
$stateRoot = Join-Path $env:ProgramData 'Arvectum\ProxyLauncher\wfp-test'
$testSigningMarker = Join-Path $stateRoot 'testsigning-owned'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required.'
    }
}

function Remove-TestService {
    & sc.exe stop $serviceName 2>$null | Out-Null
    & sc.exe delete $serviceName 2>$null | Out-Null
    Start-Sleep -Milliseconds 500
}

Assert-Administrator
$DriverPath = (Resolve-Path $DriverPath).Path
$CertificatePath = (Resolve-Path $CertificatePath).Path
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
$cert = Import-Certificate -FilePath $CertificatePath -CertStoreLocation 'Cert:\LocalMachine\Root'
Import-Certificate -FilePath $CertificatePath -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null

Remove-TestService
& sc.exe create $serviceName type= kernel start= demand binPath= $DriverPath | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to create kernel service.'
}
& sc.exe start $serviceName | Out-Host
$startExit = $LASTEXITCODE

if ($startExit -eq 0) {
    $state = & sc.exe query $serviceName | Out-String
    if ($state -notmatch 'STATE\s+:\s+4\s+RUNNING') {
        Remove-TestService
        throw 'WFP callout driver did not reach RUNNING state.'
    }
    Write-Output ('ARVECTUM_WFP_DRIVER_READY thumbprint=' + $cert.Thumbprint)
    exit 0
}

Remove-TestService
if (-not $EnableTestSigning) {
    throw ('Driver load failed with sc.exe exit code ' + $startExit + '. Re-run with -EnableTestSigning only if this is the isolated test stand.')
}

& bcdedit.exe /set testsigning on | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to enable Windows test signing. Secure Boot or device policy may prohibit this change.'
}
Set-Content -Path $testSigningMarker -Value 'Arvectum enabled testsigning for WFP acceptance.'
Write-Output 'ARVECTUM_WFP_REBOOT_REQUIRED'
exit 3010
