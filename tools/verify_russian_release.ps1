<#
.SYNOPSIS
    Consumer-side Russian release verification for APL-REL-012.
.DESCRIPTION
    Verifies the SHA-256 manifest, every listed release asset, the detached
    CryptoPro CMS/PKCS#7 signature, and the signer identity for an Arvectum
    Proxy Launcher Russian release.

    This tool distinguishes three separate properties:
      1. file integrity (SHA-256 hashes),
      2. qualified release authenticity (CryptoPro detached signature + signer),
      3. OS-native publisher trust (Authenticode/SmartScreen), which is NOT
         implied by a successful APL-REL-012 verification.

    The current approved release-evidence certificate is the ООО «Арвектум»
    FNS-issued certificate proven in APL-REL-010. The expected thumbprint is
    pinned by default and must be deliberately changed when the governed
    certificate is renewed or replaced.
#>

[CmdletBinding()]
param(
    [string]$ReleaseDirectory = $PSScriptRoot,

    [ValidatePattern('^[0-9A-Fa-f\s]{40,64}$')]
    [string]$ExpectedSignerThumbprint = 'EE1CFA955BA22F03C39C76B183D94CD37494582E'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-Thumbprint([string]$Thumbprint) {
    return (($Thumbprint -replace '\s', '').ToUpperInvariant())
}

function Resolve-CspTest {
    if ($env:CRYPTO_PRO_CSPTEST_PATH) {
        if (-not (Test-Path -LiteralPath $env:CRYPTO_PRO_CSPTEST_PATH -PathType Leaf)) {
            throw "CRYPTO_PRO_CSPTEST_PATH указывает на несуществующий файл: $env:CRYPTO_PRO_CSPTEST_PATH"
        }
        return (Resolve-Path -LiteralPath $env:CRYPTO_PRO_CSPTEST_PATH).Path
    }

    $command = Get-Command 'csptest.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @()
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'Crypto Pro\CSP\csptest.exe') }
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Crypto Pro\CSP\csptest.exe') }
    $candidate = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($candidate) { return (Resolve-Path -LiteralPath $candidate).Path }

    throw 'CryptoPro CSP не найден. Установите CryptoPro CSP или задайте CRYPTO_PRO_CSPTEST_PATH.'
}

function Invoke-CspTest([string[]]$Arguments) {
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # CryptoPro may emit informational diagnostics on stderr even when its
        # native exit code is zero. Windows PowerShell 5.1 turns such stderr into
        # NativeCommandError under Stop, so capture it under Continue and decide
        # success from LASTEXITCODE plus the explicit verification markers.
        $ErrorActionPreference = 'Continue'
        $rawOutput = & $script:CspTest @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $output = @($rawOutput | ForEach-Object { $_.ToString() })
    if ($exitCode -ne 0) {
        throw "CryptoPro csptest завершился с кодом $exitCode. Вывод: $($output -join ' | ')"
    }
    return $output
}

function Get-CmsSignerCertificate([string]$ManifestPath, [string]$SignaturePath) {
    Add-Type -AssemblyName System.Security
    $contentInfo = [System.Security.Cryptography.Pkcs.ContentInfo]::new(
        [System.IO.File]::ReadAllBytes($ManifestPath)
    )
    $signedCms = [System.Security.Cryptography.Pkcs.SignedCms]::new($contentInfo, $true)
    $signedCms.Decode([System.IO.File]::ReadAllBytes($SignaturePath))

    if ($signedCms.SignerInfos.Count -ne 1) {
        throw "Ожидалась ровно одна подпись в CMS, найдено: $($signedCms.SignerInfos.Count)."
    }

    $certificate = $signedCms.SignerInfos[0].Certificate
    if (-not $certificate) {
        throw 'В CMS-подписи отсутствует сертификат подписанта. Публикация не соответствует контракту APL-REL-011.'
    }
    return $certificate
}

try {
    Write-Host 'Arvectum Proxy Launcher — проверка российского релиза'
    Write-Host '-------------------------------------------------------'

    if ($env:OS -ne 'Windows_NT') {
        throw 'Эта автоматическая проверка рассчитана на Windows с установленным CryptoPro CSP.'
    }

    if (-not (Test-Path -LiteralPath $ReleaseDirectory -PathType Container)) {
        throw "Папка релиза не найдена: $ReleaseDirectory"
    }
    $releasePath = (Resolve-Path -LiteralPath $ReleaseDirectory).Path

    $manifestPath = Join-Path $releasePath 'SHA256SUMS.txt'
    $signaturePath = Join-Path $releasePath 'SHA256SUMS.txt.sig'
    $certificatePath = Join-Path $releasePath 'signer-certificate.cer'
    $evidencePath = Join-Path $releasePath 'signing-evidence.json'

    foreach ($required in @($manifestPath, $signaturePath, $certificatePath, $evidencePath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Не хватает обязательного файла проверки: $([System.IO.Path]::GetFileName($required))"
        }
    }

    $evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($evidence.product -ne 'Arvectum Proxy Launcher') { throw 'Некорректный product в signing-evidence.json.' }
    if ($evidence.signing_mode -ne 'russian-qualified-evidence') { throw 'Некорректный signing_mode в signing-evidence.json.' }
    if ($evidence.embedded_code_signing_activated -ne $false) { throw 'Evidence неожиданно заявляет активированную embedded code signing.' }
    if ($evidence.detached_signature_verified -ne $true) { throw 'Evidence не подтверждает успешную detached-проверку при выпуске.' }

    $actualManifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualManifestHash -ne ([string]$evidence.manifest_sha256).ToLowerInvariant()) {
        throw 'SHA256SUMS.txt не совпадает с signing-evidence.json.'
    }

    $actualSignatureHash = (Get-FileHash -LiteralPath $signaturePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSignatureHash -ne ([string]$evidence.manifest_signature_sha256).ToLowerInvariant()) {
        throw 'SHA256SUMS.txt.sig не совпадает с signing-evidence.json.'
    }

    $manifestEntries = @{}
    $verifiedCount = 0
    foreach ($line in Get-Content -LiteralPath $manifestPath -Encoding ASCII) {
        if ([string]::IsNullOrWhiteSpace($line)) { throw 'SHA256SUMS.txt содержит пустую строку.' }
        if ($line -notmatch '^([0-9a-fA-F]{64})  (.+)$') { throw "Некорректная строка SHA256SUMS.txt: $line" }

        $expectedHash = $Matches[1].ToLowerInvariant()
        $name = $Matches[2]
        if ([System.IO.Path]::IsPathRooted($name) -or $name.Contains('\') -or $name.Contains('/') -or $name -in @('.', '..')) {
            throw "Недопустимое имя файла в манифесте: $name"
        }

        $key = $name.ToLowerInvariant()
        if ($manifestEntries.ContainsKey($key)) { throw "Дублирующееся имя файла в манифесте: $name" }

        $assetPath = Join-Path $releasePath $name
        if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) { throw "Файл из манифеста отсутствует: $name" }

        $actualHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) { throw "Нарушена целостность файла: $name" }

        $manifestEntries[$key] = [pscustomobject]@{ name = $name; sha256 = $expectedHash; path = $assetPath }
        $verifiedCount += 1
    }

    if ($verifiedCount -lt 1) { throw 'Манифест не содержит ни одного файла релиза.' }

    $allowedUnlisted = @(
        'sha256sums.txt',
        'sha256sums.txt.sig',
        'signer-certificate.cer',
        'signing-evidence.json'
    )
    foreach ($file in Get-ChildItem -LiteralPath $releasePath -File) {
        $key = $file.Name.ToLowerInvariant()
        if (-not $manifestEntries.ContainsKey($key) -and $allowedUnlisted -notcontains $key) {
            throw "В папке релиза найден неподписанный/неучтённый файл: $($file.Name)"
        }
    }

    $evidenceAssets = @{}
    foreach ($record in @($evidence.assets)) {
        $key = ([string]$record.name).ToLowerInvariant()
        if ($evidenceAssets.ContainsKey($key)) { throw "Дублирующийся asset в signing-evidence.json: $($record.name)" }
        $evidenceAssets[$key] = $record
    }
    foreach ($key in $manifestEntries.Keys) {
        if (-not $evidenceAssets.ContainsKey($key)) { throw "Файл из манифеста отсутствует в signing-evidence.json: $($manifestEntries[$key].name)" }
        if (([string]$evidenceAssets[$key].sha256).ToLowerInvariant() -ne $manifestEntries[$key].sha256) {
            throw "Хэш asset расходится между манифестом и signing-evidence.json: $($manifestEntries[$key].name)"
        }
    }

    $script:CspTest = Resolve-CspTest
    $verifyOutput = Invoke-CspTest @(
        '-sfsign', '-verify', '-detached',
        '-in', $manifestPath,
        '-signature', $signaturePath
    )
    $verifyText = ($verifyOutput -join "`n")
    $signatureVerified = ($verifyText -match 'verified\s+OK') -or ($verifyText -match 'ErrorCode:\s*0x00000000')
    if (-not $signatureVerified) { throw 'CryptoPro не подтвердил detached-подпись SHA256SUMS.txt.' }

    $cmsSigner = Get-CmsSignerCertificate -ManifestPath $manifestPath -SignaturePath $signaturePath
    $exportedSigner = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)

    $expectedThumbprint = Normalize-Thumbprint $ExpectedSignerThumbprint
    $cmsThumbprint = Normalize-Thumbprint $cmsSigner.Thumbprint
    $exportedThumbprint = Normalize-Thumbprint $exportedSigner.Thumbprint
    $evidenceThumbprint = Normalize-Thumbprint ([string]$evidence.signer_thumbprint)

    if ($cmsThumbprint -ne $expectedThumbprint) {
        throw "Подпись создана неожиданным сертификатом: $cmsThumbprint. Ожидался: $expectedThumbprint"
    }
    if ($exportedThumbprint -ne $cmsThumbprint) { throw 'signer-certificate.cer не совпадает с сертификатом внутри CMS-подписи.' }
    if ($evidenceThumbprint -ne $cmsThumbprint) { throw 'Thumbprint в signing-evidence.json не совпадает с сертификатом внутри CMS-подписи.' }
    if ($cmsSigner.Subject -notmatch 'АРВЕКТУМ') { throw "Сертификат подписанта не идентифицирует Арвектум: $($cmsSigner.Subject)" }

    Write-Host ''
    Write-Host 'APL_REL_012_RESULT=PASS'
    Write-Host 'РЕЗУЛЬТАТ: ПРОВЕРКА ПРОЙДЕНА' -ForegroundColor Green
    Write-Host "Файлов проверено по SHA-256: $verifiedCount"
    Write-Host 'Криптографическая целостность: ПОДТВЕРЖДЕНА'
    Write-Host 'Detached CryptoPro signature: ПОДТВЕРЖДЕНА'
    Write-Host "Подписант: $($cmsSigner.Subject)"
    Write-Host "Издатель сертификата: $($cmsSigner.Issuer)"
    Write-Host "Thumbprint: $cmsThumbprint"
    Write-Host 'Подлинность российского release manifest: ПОДТВЕРЖДЕНА'
    Write-Host ''
    Write-Host 'ВАЖНО: эта проверка НЕ означает, что EXE имеет Microsoft Authenticode-подпись,' -ForegroundColor Yellow
    Write-Host 'НЕ означает репутацию SmartScreen и НЕ доказывает нативное доверие Windows к издателю.' -ForegroundColor Yellow
    Write-Host 'Текущий сертификат классифицирован как RELEASE-EVIDENCE-ONLY.' -ForegroundColor Yellow
    exit 0
}
catch {
    Write-Host ''
    Write-Host 'APL_REL_012_RESULT=FAIL'
    Write-Host 'РЕЗУЛЬТАТ: ПРОВЕРКА НЕ ПРОЙДЕНА' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'Не запускайте файлы из этого релиза до получения исправного пакета из официального канала Арвектум.' -ForegroundColor Yellow
    exit 1
}
