param(
    [Parameter(Mandatory=$true)][string]$CertificatePath
)

$ErrorActionPreference = 'Stop'
$serviceName = 'ArvectumProxyRoutingCallout'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator privileges are required.'
}

& sc.exe stop $serviceName 2>$null | Out-Null
& sc.exe delete $serviceName 2>$null | Out-Null

$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new((Resolve-Path $CertificatePath).Path)
foreach ($storeName in @('Root','TrustedPublisher')) {
    $store = [Security.Cryptography.X509Certificates.X509Store]::new(
        $storeName,
        [Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )
    $store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    try {
        $matches = $store.Certificates | Where-Object Thumbprint -eq $certificate.Thumbprint
        foreach ($item in $matches) {
            $store.Remove($item)
        }
    } finally {
        $store.Close()
    }
}
Write-Output 'ARVECTUM_WFP_TEST_ROLLBACK_COMPLETE'
