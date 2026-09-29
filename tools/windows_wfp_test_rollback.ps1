param(
    [Parameter(Mandatory=$true)][string]$CertificatePath
)

$ErrorActionPreference = 'Stop'
$serviceName = 'ArvectumProxyRoutingCallout'
$stateRoot = Join-Path $env:ProgramData 'Arvectum\ProxyLauncher\wfp-test'
$testSigningMarker = Join-Path $stateRoot 'testsigning-owned'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator privileges are required.'
}

& sc.exe stop $serviceName 2>$null | Out-Null
& sc.exe delete $serviceName 2>$null | Out-Null

$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new((Resolve-Path $CertificatePath).Path)
foreach ($storeName in @('Root','TrustedPublisher')) {
    & certutil.exe -delstore $storeName $certificate.Thumbprint 2>$null | Out-Null
}

if (Test-Path $testSigningMarker) {
    & bcdedit.exe /set testsigning off | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw 'Driver/certificate rollback succeeded, but Arvectum-owned test signing could not be disabled.'
    }
    Remove-Item $testSigningMarker -Force
    Write-Output 'ARVECTUM_WFP_TEST_ROLLBACK_COMPLETE_REBOOT_REQUIRED'
    exit 3010
}
Write-Output 'ARVECTUM_WFP_TEST_ROLLBACK_COMPLETE'
