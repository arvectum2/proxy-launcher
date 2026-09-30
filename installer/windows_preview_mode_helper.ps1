[CmdletBinding()]
param(
    [ValidateSet('Enable','Disable','Status')]
    [string]$Action = 'Status',
    [string]$CertificatePath,
    [switch]$Elevated
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProgramDataRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
$SystemRootPath = [Environment]::GetEnvironmentVariable('SystemRoot', [EnvironmentVariableTarget]::Machine)
if ([string]::IsNullOrWhiteSpace($ProgramDataRoot) -or [string]::IsNullOrWhiteSpace($SystemRootPath)) {
    throw 'Required Windows system folders could not be resolved.'
}
$StateRoot = Join-Path $ProgramDataRoot 'Arvectum\ProxyLauncher'
$MarkerPath = Join-Path $StateRoot 'windows-preview-mode.json'
$Schema = 'arvectum.proxy.windows-preview-mode.v1'
$BcdEdit = Join-Path $SystemRootPath 'System32\bcdedit.exe'

function Is-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-TestSigningEnabled {
    $output = & $BcdEdit /enum '{current}' 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Could not read current BCD entry.' }
    $line = @($output | Where-Object { [string]$_ -match '(?i)^\s*testsigning\s+' } | Select-Object -First 1)
    if ($line.Count -eq 0) { return $false }
    return [string]$line[0] -match '(?i)\b(yes|on|true|1|да)\b'
}

function Read-Marker {
    if (-not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) { return $null }
    $payload = Get-Content -LiteralPath $MarkerPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]$payload.schema -cne $Schema) {
        throw 'Windows preview mode marker schema mismatch.'
    }
    return $payload
}

function Write-Marker($Payload) {
    New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
    $Payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $MarkerPath -Encoding utf8
}

function Certificate-InStore([string]$Store, [string]$Thumbprint) {
    return Test-Path -LiteralPath ("Cert:\LocalMachine\{0}\{1}" -f $Store,$Thumbprint)
}

function Import-PreviewCertificate([string]$Path, [string]$Store) {
    Import-Certificate -FilePath $Path -CertStoreLocation ("Cert:\LocalMachine\{0}" -f $Store) | Out-Null
}

function Remove-OwnedCertificate([string]$Store, [string]$Thumbprint, [bool]$Owned) {
    if (-not $Owned -or [string]::IsNullOrWhiteSpace($Thumbprint)) { return }
    $path = "Cert:\LocalMachine\{0}\{1}" -f $Store,$Thumbprint
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

function Invoke-Elevated {
    $powershell = Join-Path $SystemRootPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -Elevated' -f $PSCommandPath,$Action
    if ($CertificatePath) {
        $arguments += (' -CertificatePath "{0}"' -f $CertificatePath)
    }
    $process = Start-Process -FilePath $powershell -Verb RunAs -ArgumentList $arguments -PassThru -Wait
    exit $process.ExitCode
}

if (-not $Elevated -and $Action -ne 'Status' -and -not (Is-Administrator)) {
    Invoke-Elevated
}

try {
    if ($Action -eq 'Status') {
        $marker = Read-Marker
        $testSigning = Test-TestSigningEnabled
        if ($null -eq $marker) {
            Write-Output "ARVECTUM_WINDOWS_PREVIEW_MODE_DISABLED testsigning=$([int]$testSigning)"
            exit 1
        }
        Write-Output ("ARVECTUM_WINDOWS_PREVIEW_MODE_STATUS testsigning={0} thumbprint={1}" -f [int]$testSigning,[string]$marker.certificate_thumbprint)
        exit 0
    }

    if (-not (Is-Administrator)) {
        throw 'Administrator privileges are required.'
    }

    if ($Action -eq 'Enable') {
        if ([string]::IsNullOrWhiteSpace($CertificatePath) -or -not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
            throw 'Preview certificate file is required.'
        }
        $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new((Resolve-Path -LiteralPath $CertificatePath).Path)
        $thumbprint = [string]$certificate.Thumbprint
        if ([string]::IsNullOrWhiteSpace($thumbprint)) { throw 'Preview certificate thumbprint is empty.' }

        $existing = Read-Marker
        if ($null -ne $existing -and [string]$existing.certificate_thumbprint -cne $thumbprint) {
            throw 'A different Arvectum preview-mode certificate is already owned by this machine.'
        }

        $rootOwned = -not (Certificate-InStore 'Root' $thumbprint)
        $publisherOwned = -not (Certificate-InStore 'TrustedPublisher' $thumbprint)
        if ($rootOwned) { Import-PreviewCertificate $CertificatePath 'Root' }
        if ($publisherOwned) { Import-PreviewCertificate $CertificatePath 'TrustedPublisher' }

        $wasEnabled = Test-TestSigningEnabled
        $testSigningOwned = -not $wasEnabled
        if ($testSigningOwned) {
            & $BcdEdit /set testsigning on | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Could not enable Windows test-signing mode.' }
        }

        Write-Marker ([ordered]@{
            schema = $Schema
            certificate_thumbprint = $thumbprint
            certificate_subject = [string]$certificate.Subject
            root_certificate_owned = [bool]$rootOwned
            trusted_publisher_certificate_owned = [bool]$publisherOwned
            testsigning_owned = [bool]$testSigningOwned
            enabled_utc = [DateTime]::UtcNow.ToString('o')
        })
        Write-Output ("ARVECTUM_WINDOWS_PREVIEW_MODE_ENABLED thumbprint={0} reboot_required={1}" -f $thumbprint,[int]$testSigningOwned)
        if ($testSigningOwned) { exit 3010 }
        exit 0
    }

    if ($Action -eq 'Disable') {
        $marker = Read-Marker
        if ($null -eq $marker) {
            Write-Output 'ARVECTUM_WINDOWS_PREVIEW_MODE_ALREADY_DISABLED'
            exit 0
        }
        $thumbprint = [string]$marker.certificate_thumbprint
        Remove-OwnedCertificate 'Root' $thumbprint ([bool]$marker.root_certificate_owned)
        Remove-OwnedCertificate 'TrustedPublisher' $thumbprint ([bool]$marker.trusted_publisher_certificate_owned)

        $restartRequired = $false
        if ([bool]$marker.testsigning_owned) {
            & $BcdEdit /set testsigning off | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Could not disable Windows test-signing mode.' }
            $restartRequired = $true
        }
        Remove-Item -LiteralPath $MarkerPath -Force -ErrorAction Stop
        Write-Output ("ARVECTUM_WINDOWS_PREVIEW_MODE_DISABLED reboot_required={0}" -f [int]$restartRequired)
        exit 0
    }

    throw "Unsupported action: $Action"
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
