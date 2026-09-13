<#
.SYNOPSIS
    Authenticode signing and verification foundation for Arvectum Proxy Launcher.
.DESCRIPTION
    Signs or verifies Windows PE artifacts using SignTool and a code-signing certificate
    already available through the Windows certificate store. The script never accepts
    a PFX file or private-key password. Production signing requires SHA-256 and an
    RFC 3161 timestamp; -SkipTimestamp exists only for isolated CI/self-signed smoke tests.

    APL-REL-016 additionally requires an RSA code-signing identity with a minimum
    2048-bit public key so the production profile is compatible with the Windows
    public-trust / Smart App Control baseline.
#>

[CmdletBinding()]
param(
    [ValidateSet('Sign', 'Verify', 'Inspect')]
    [string]$Mode = 'Verify',

    [Parameter(Mandatory = $true)]
    [string[]]$Path,

    [string]$CertificateThumbprint = $env:WINDOWS_SIGNING_CERT_THUMBPRINT,

    [ValidateSet('CurrentUser', 'LocalMachine')]
    [string]$CertificateStoreLocation = 'CurrentUser',

    [string]$TimestampUrl = $env:WINDOWS_SIGNING_TIMESTAMP_URL,

    [string]$ExpectedPublisher = $env:WINDOWS_SIGNING_EXPECTED_PUBLISHER,

    [switch]$SkipTimestamp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Authenticode operations must run on Windows.'
}

function Resolve-SignTool {
    if ($env:SIGNTOOL_PATH) {
        if (-not (Test-Path -LiteralPath $env:SIGNTOOL_PATH -PathType Leaf)) {
            throw "SIGNTOOL_PATH does not exist: $env:SIGNTOOL_PATH"
        }
        return (Resolve-Path -LiteralPath $env:SIGNTOOL_PATH).Path
    }

    $command = Get-Command 'signtool.exe' -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kitsRoot -PathType Container) {
        $candidates = Get-ChildItem -LiteralPath $kitsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\signtool.exe' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
        $candidate = $candidates | Select-Object -First 1
        if ($candidate) {
            return $candidate
        }
    }

    throw 'signtool.exe was not found. Install a Windows SDK or set SIGNTOOL_PATH.'
}

function Resolve-Targets([string[]]$InputPaths) {
    $targets = @()
    foreach ($item in $InputPaths) {
        $resolvedItems = Resolve-Path -Path $item -ErrorAction Stop
        foreach ($resolved in $resolvedItems) {
            if (-not (Test-Path -LiteralPath $resolved.Path -PathType Leaf)) {
                throw "Authenticode target must be a file: $($resolved.Path)"
            }
            $targets += $resolved.Path
        }
    }
    return @($targets | Select-Object -Unique)
}

function Invoke-SignTool([string[]]$Arguments) {
    $output = & $script:SignTool @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $output | ForEach-Object { Write-Host $_ }
        throw "SignTool failed with exit code ${LASTEXITCODE}: $($Arguments -join ' ')"
    }
    $output | ForEach-Object { Write-Host $_ }
}

function Get-CodeSigningCertificate([string]$Thumbprint) {
    if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
        throw 'A code-signing certificate thumbprint is required. Set WINDOWS_SIGNING_CERT_THUMBPRINT or pass -CertificateThumbprint.'
    }

    $normalized = ($Thumbprint -replace '\s', '').ToUpperInvariant()
    $certPath = "Cert:\$CertificateStoreLocation\My\$normalized"
    if (-not (Test-Path -LiteralPath $certPath)) {
        throw "Code-signing certificate was not found at $certPath"
    }

    $certificate = Get-Item -LiteralPath $certPath
    if (-not $certificate.HasPrivateKey) {
        throw "Certificate $normalized does not expose an accessible private key."
    }

    $codeSigningOid = '1.3.6.1.5.5.7.3.3'
    $hasCodeSigningEku = $false
    foreach ($extension in $certificate.Extensions) {
        if ($extension.Oid.Value -eq '2.5.29.37') {
            $eku = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]$extension
            foreach ($oid in $eku.EnhancedKeyUsages) {
                if ($oid.Value -eq $codeSigningOid) {
                    $hasCodeSigningEku = $true
                    break
                }
            }
        }
    }
    if (-not $hasCodeSigningEku) {
        throw "Certificate $normalized does not contain the Code Signing EKU ($codeSigningOid)."
    }

    $rsaOid = '1.2.840.113549.1.1.1'
    if ($certificate.PublicKey.Oid.Value -ne $rsaOid) {
        throw "Certificate $normalized must use RSA for the APL-REL-016 Windows public-trust profile. Actual public-key OID: $($certificate.PublicKey.Oid.Value)"
    }
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
    if (-not $rsa) {
        throw "Certificate $normalized declares RSA but no RSA public key could be resolved."
    }
    try {
        if ($rsa.KeySize -lt 2048) {
            throw "Certificate $normalized RSA key size is $($rsa.KeySize) bits; APL-REL-016 requires at least 2048 bits."
        }
    } finally {
        $rsa.Dispose()
    }

    return $certificate
}

function Get-SignatureInfo([string]$Target) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Target
    $subject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
    [pscustomobject]@{
        Path       = $Target
        Status     = $signature.Status.ToString()
        StatusText = $signature.StatusMessage
        Publisher  = $subject
        Thumbprint = if ($signature.SignerCertificate) { $signature.SignerCertificate.Thumbprint } else { $null }
    }
}

function Assert-ExpectedPublisher([object]$SignatureInfo) {
    if ([string]::IsNullOrWhiteSpace($ExpectedPublisher)) {
        return
    }
    if ($SignatureInfo.Publisher -ne $ExpectedPublisher) {
        throw "Publisher mismatch for '$($SignatureInfo.Path)'. Expected '$ExpectedPublisher', got '$($SignatureInfo.Publisher)'."
    }
}

function Verify-Target([string]$Target) {
    Invoke-SignTool @('verify', '/pa', '/all', '/v', $Target)
    $info = Get-SignatureInfo $Target
    if ($info.Status -ne 'Valid') {
        throw "Authenticode verification failed for '$Target': $($info.Status) - $($info.StatusText)"
    }
    Assert-ExpectedPublisher $info
    Write-Host "Authenticode verify PASS: $Target"
    return $info
}

$script:SignTool = Resolve-SignTool
$targets = @(Resolve-Targets $Path)
if ($targets.Count -eq 0) {
    throw 'No Authenticode targets were resolved.'
}

switch ($Mode) {
    'Inspect' {
        $targets | ForEach-Object { Get-SignatureInfo $_ }
        break
    }

    'Verify' {
        $targets | ForEach-Object { Verify-Target $_ }
        break
    }

    'Sign' {
        $certificate = Get-CodeSigningCertificate $CertificateThumbprint
        $normalizedThumbprint = ($certificate.Thumbprint -replace '\s', '').ToUpperInvariant()

        if (-not $SkipTimestamp -and [string]::IsNullOrWhiteSpace($TimestampUrl)) {
            throw 'Production Authenticode signing requires an RFC 3161 timestamp URL. Set WINDOWS_SIGNING_TIMESTAMP_URL or pass -TimestampUrl. Use -SkipTimestamp only for isolated test certificates.'
        }

        foreach ($target in $targets) {
            $arguments = @(
                'sign',
                '/sha1', $normalizedThumbprint,
                '/s', 'My',
                '/fd', 'SHA256',
                '/d', 'Arvectum Proxy Launcher'
            )
            if ($CertificateStoreLocation -eq 'LocalMachine') {
                $arguments += '/sm'
            }
            if (-not $SkipTimestamp) {
                $arguments += @('/tr', $TimestampUrl, '/td', 'SHA256')
            }
            $arguments += @('/v', $target)

            Invoke-SignTool $arguments
            $verified = Verify-Target $target
            Write-Host "Authenticode sign PASS: $target; publisher=$($verified.Publisher); thumbprint=$($verified.Thumbprint)"
        }
        break
    }
}
