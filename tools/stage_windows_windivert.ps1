[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$SourceArchive
)

$ErrorActionPreference = "Stop"

$Version = "2.2.2"
$ArchiveName = "WinDivert-2.2.2-A.zip"
$ReleaseUrl = "https://github.com/basil00/WinDivert/releases/download/v2.2.2/$ArchiveName"
$ArchiveSha256 = "63CB41763BB4B20F600B6DE04E991A9C2BE73279E317D4D82F237B150C5F3F15"
$DllSha256 = "C1E060EE19444A259B2162F8AF0F3FE8C4428A1C6F694DCE20DE194AC8D7D9A2"
$DriverSha256 = "8DA085332782708D8767BCACE5327A6EC7283C17CFB85E40B03CD2323A90DDC2"
$LicenseSha256 = "14A0CB5214D536E4FDAE6AA3F5696F981EEDA106CD026E9794BBA489EE79D628"
$HeaderSha256 = "5017A1768C1592FD664C0C2D3D2D30F81FAD4AB98D322B1914C6F0A33FCACDF9"
$LibSha256 = "C5678D544EB0121A189D1139F54E0C67854DC64D1C897111A27EF2E52CB38EB3"
$ExpectedDriverThumbprint = "043589F75FCE2795E7F2CC3E526D46784D5DDAB3"

function Assert-Sha256 {
    param([string]$Path, [string]$Expected)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required WinDivert file is absent: $Path"
    }
    $Actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($Actual -ne $Expected.ToUpperInvariant()) {
        throw "SHA256 mismatch for $Path. Expected $Expected, got $Actual."
    }
    return $Actual
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "arvectum-windivert-" + [Guid]::NewGuid().ToString("N")
)
New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

try {
    $ArchivePath = Join-Path $TempRoot $ArchiveName
    if ($SourceArchive) {
        $ResolvedArchive = (Resolve-Path -LiteralPath $SourceArchive).Path
        Copy-Item -LiteralPath $ResolvedArchive -Destination $ArchivePath -Force
    }
    else {
        Invoke-WebRequest -Uri $ReleaseUrl -OutFile $ArchivePath -UseBasicParsing
    }

    $ArchiveHash = Assert-Sha256 -Path $ArchivePath -Expected $ArchiveSha256
    $Expanded = Join-Path $TempRoot "expanded"
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Expanded -Force
    $Root = Join-Path $Expanded "WinDivert-2.2.2-A"
    $Dll = Join-Path $Root "x64\WinDivert.dll"
    $Driver = Join-Path $Root "x64\WinDivert64.sys"
    $License = Join-Path $Root "LICENSE"
    $Header = Join-Path $Root "include\windivert.h"
    $Lib = Join-Path $Root "x64\WinDivert.lib"

    $DllHash = Assert-Sha256 -Path $Dll -Expected $DllSha256
    $DriverHash = Assert-Sha256 -Path $Driver -Expected $DriverSha256
    $LicenseHash = Assert-Sha256 -Path $License -Expected $LicenseSha256
    $HeaderHash = Assert-Sha256 -Path $Header -Expected $HeaderSha256
    $LibHash = Assert-Sha256 -Path $Lib -Expected $LibSha256

    $Signature = Get-AuthenticodeSignature -LiteralPath $Driver
    if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "WinDivert64.sys Authenticode verification failed: $($Signature.Status)"
    }
    if ($null -eq $Signature.SignerCertificate) {
        throw "WinDivert64.sys signer certificate is absent"
    }
    $Thumbprint = $Signature.SignerCertificate.Thumbprint.ToUpperInvariant()
    if ($Thumbprint -ne $ExpectedDriverThumbprint) {
        throw "Unexpected WinDivert64.sys signer thumbprint: $Thumbprint"
    }
    $Output = [System.IO.Path]::GetFullPath($OutputDirectory)
    if (Test-Path -LiteralPath $Output) {
        Remove-Item -LiteralPath $Output -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Output -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Output "sdk") -Force | Out-Null

    Copy-Item -LiteralPath $Dll -Destination (Join-Path $Output "WinDivert.dll")
    Copy-Item -LiteralPath $Driver -Destination (Join-Path $Output "WinDivert64.sys")
    Copy-Item -LiteralPath $License -Destination (Join-Path $Output "WinDivert-LICENSE")
    Copy-Item -LiteralPath $Header -Destination (Join-Path $Output "sdk\windivert.h")
    Copy-Item -LiteralPath $Lib -Destination (Join-Path $Output "sdk\WinDivert.lib")

    $Manifest = [ordered]@{
        schema = "arvectum.proxy.windivert-dependency.v1"
        version = $Version
        release_tag = "v2.2.2"
        source_url = $ReleaseUrl
        archive_sha256 = $ArchiveHash
        license = "LGPL-3.0-or-later OR GPL-2.0"
        driver_signature_status = [string]$Signature.Status
        driver_signer_thumbprint = $Thumbprint
        files = [ordered]@{
            "WinDivert.dll" = $DllHash
            "WinDivert64.sys" = $DriverHash
            "WinDivert-LICENSE" = $LicenseHash
            "sdk/windivert.h" = $HeaderHash
            "sdk/WinDivert.lib" = $LibHash
        }
    }
    $ManifestPath = Join-Path $Output "windivert-dependency.json"
    $Manifest | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $ManifestPath -Encoding UTF8

    Write-Output (
        "ARVECTUM_WINDIVERT_STAGED version={0} driver_sha256={1} signer={2}" -f
        $Version, $DriverHash, $Thumbprint
    )
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}
