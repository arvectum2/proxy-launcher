<#
.SYNOPSIS
    APL-REL-016 physical/public Windows trust evidence collector and fail-closed gate.
.DESCRIPTION
    Verifies the exact application and Setup Authenticode identities, RSA/code-signing
    profile, Windows chain build, Mark-of-the-Web on the public Setup download, Defender
    state and operator-recorded SmartScreen / Smart App Control outcomes.

    The gate does not infer Microsoft Trusted Root Program membership from a local root
    store alone. A real public-readiness decision therefore requires an explicit
    MicrosoftTrustedRootProgramReference pointing to retained authoritative evidence.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApplicationPath,

    [Parameter(Mandatory = $true)]
    [string]$SetupPath,

    [string]$ExpectedPublisher = $env:WINDOWS_SIGNING_EXPECTED_PUBLISHER,

    [string]$ExpectedThumbprint = $env:WINDOWS_SIGNING_CERT_THUMBPRINT,

    [string]$MicrosoftTrustedRootProgramReference,

    [ValidateSet('NotTested', 'NoWarning', 'UnrecognizedAppVerifiedPublisher', 'UnrecognizedAppUnknownPublisher', 'Blocked')]
    [string]$SmartScreenOutcome = 'NotTested',

    [ValidateSet('Unknown', 'Off', 'Evaluation', 'Enforced')]
    [string]$SmartAppControlState = 'Unknown',

    [ValidateSet('NotTested', 'Allowed', 'Blocked')]
    [string]$SmartAppControlLaunch = 'NotTested',

    [switch]$RequireMotw,

    [switch]$RequirePublicReady,

    [switch]$RequireNoSmartScreenWarning,

    [string]$OutputPath = (Join-Path (Get-Location) 'apl-rel-016-windows-public-trust.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'APL-REL-016 public-trust acceptance must run on Windows.'
}

$CodeSigningEkuOid = '1.3.6.1.5.5.7.3.3'
$RsaOid = '1.2.840.113549.1.1.1'

function Normalize-Thumbprint([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    return ($Value -replace '\s', '').ToUpperInvariant()
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-CodeSigningEkuPresent([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate) {
    foreach ($extension in $Certificate.Extensions) {
        if ($extension.Oid.Value -eq '2.5.29.37') {
            $eku = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]$extension
            foreach ($oid in $eku.EnhancedKeyUsages) {
                if ($oid.Value -eq $script:CodeSigningEkuOid) { return $true }
            }
        }
    }
    return $false
}

function Get-RsaKeyBits([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate) {
    if ($Certificate.PublicKey.Oid.Value -ne $script:RsaOid) { return 0 }
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($Certificate)
    if (-not $rsa) { return 0 }
    try {
        return $rsa.KeySize
    } finally {
        $rsa.Dispose()
    }
}

function Build-CertificateChain([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate) {
    $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
    try {
        $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
        $chain.ChainPolicy.RevocationFlag = [System.Security.Cryptography.X509Certificates.X509RevocationFlag]::EntireChain
        $chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag
        $chain.ChainPolicy.UrlRetrievalTimeout = [TimeSpan]::FromSeconds(30)
        $built = $chain.Build($Certificate)
        $statuses = @($chain.ChainStatus | ForEach-Object { $_.Status.ToString() + ': ' + $_.StatusInformation.Trim() })
        $root = if ($chain.ChainElements.Count -gt 0) { $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate } else { $null }
        return [pscustomobject]@{
            Built = $built
            Status = $statuses
            RootSubject = if ($root) { $root.Subject } else { $null }
            RootThumbprint = if ($root) { (Normalize-Thumbprint $root.Thumbprint) } else { $null }
        }
    } finally {
        $chain.Dispose()
    }
}

function Test-RootStorePresence([string]$Thumbprint) {
    if ([string]::IsNullOrWhiteSpace($Thumbprint)) { return $false }
    $locations = @(
        "Cert:\LocalMachine\AuthRoot\$Thumbprint",
        "Cert:\CurrentUser\AuthRoot\$Thumbprint",
        "Cert:\LocalMachine\Root\$Thumbprint",
        "Cert:\CurrentUser\Root\$Thumbprint"
    )
    foreach ($location in $locations) {
        if (Test-Path -LiteralPath $location) { return $true }
    }
    return $false
}

function Get-SignatureEvidence([string]$Path, [string]$Role) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Role target is not a file: $resolved"
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $resolved
    $certificate = $signature.SignerCertificate
    $status = $signature.Status.ToString()
    $publisher = if ($certificate) { $certificate.Subject } else { $null }
    $thumbprint = if ($certificate) { Normalize-Thumbprint $certificate.Thumbprint } else { $null }
    $eku = if ($certificate) { Get-CodeSigningEkuPresent $certificate } else { $false }
    $rsaBits = if ($certificate) { Get-RsaKeyBits $certificate } else { 0 }
    $chain = if ($certificate) { Build-CertificateChain $certificate } else { $null }

    return [pscustomobject][ordered]@{
        role = $Role
        filename = Split-Path -Leaf $resolved
        sha256 = Get-FileSha256 $resolved
        signature_status = $status
        publisher = $publisher
        signer_thumbprint = $thumbprint
        code_signing_eku = $eku
        public_key_algorithm_oid = if ($certificate) { $certificate.PublicKey.Oid.Value } else { $null }
        rsa_key_bits = $rsaBits
        chain_build = if ($chain) { [bool]$chain.Built } else { $false }
        chain_status = if ($chain) { @($chain.Status) } else { @() }
        root_subject = if ($chain) { $chain.RootSubject } else { $null }
        root_thumbprint = if ($chain) { $chain.RootThumbprint } else { $null }
        root_present_in_windows_trust_store = if ($chain -and $chain.RootThumbprint) { Test-RootStorePresence $chain.RootThumbprint } else { $false }
    }
}

function Get-MotwEvidence([string]$Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $raw = $null
    try {
        $raw = Get-Content -LiteralPath $resolved -Stream 'Zone.Identifier' -Raw -ErrorAction Stop
    } catch {
        return [pscustomobject][ordered]@{
            present = $false
            zone_id = $null
            host_url_present = $false
            referrer_url_present = $false
        }
    }

    $zoneId = $null
    $match = [regex]::Match($raw, '(?im)^ZoneId=(\d+)\s*$')
    if ($match.Success) { $zoneId = [int]$match.Groups[1].Value }
    return [pscustomobject][ordered]@{
        present = $true
        zone_id = $zoneId
        host_url_present = [regex]::IsMatch($raw, '(?im)^HostUrl=')
        referrer_url_present = [regex]::IsMatch($raw, '(?im)^ReferrerUrl=')
    }
}

function Get-DefenderEvidence([string[]]$TargetPaths) {
    $statusCommand = Get-Command 'Get-MpComputerStatus' -ErrorAction SilentlyContinue
    if (-not $statusCommand) {
        return [pscustomobject][ordered]@{
            available = $false
            antimalware_service_enabled = $null
            realtime_protection_enabled = $null
            related_detection_count = $null
        }
    }

    $mp = Get-MpComputerStatus
    $related = @()
    $detectionCommand = Get-Command 'Get-MpThreatDetection' -ErrorAction SilentlyContinue
    if ($detectionCommand) {
        $needles = @($TargetPaths | ForEach-Object { (Split-Path -Leaf $_).ToLowerInvariant() })
        foreach ($item in @(Get-MpThreatDetection -ErrorAction SilentlyContinue)) {
            $resources = @($item.Resources | ForEach-Object { [string]$_ })
            $joined = ($resources -join "`n").ToLowerInvariant()
            foreach ($needle in $needles) {
                if ($joined.Contains($needle)) {
                    $related += $item
                    break
                }
            }
        }
    }

    return [pscustomobject][ordered]@{
        available = $true
        antimalware_service_enabled = [bool]$mp.AMServiceEnabled
        realtime_protection_enabled = [bool]$mp.RealTimeProtectionEnabled
        related_detection_count = @($related).Count
    }
}

function Add-Failure([System.Collections.Generic.List[string]]$Failures, [string]$Message) {
    $Failures.Add($Message)
}

$resolvedApplication = (Resolve-Path -LiteralPath $ApplicationPath).Path
$resolvedSetup = (Resolve-Path -LiteralPath $SetupPath).Path
$app = Get-SignatureEvidence -Path $resolvedApplication -Role 'application'
$setup = Get-SignatureEvidence -Path $resolvedSetup -Role 'setup'
$motw = Get-MotwEvidence -Path $resolvedSetup
$defender = Get-DefenderEvidence -TargetPaths @($resolvedApplication, $resolvedSetup)
$expectedThumbprintNormalized = Normalize-Thumbprint $ExpectedThumbprint
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($artifact in @($app, $setup)) {
    if ($artifact.signature_status -cne 'Valid') { Add-Failure $failures "$($artifact.role): Authenticode status is $($artifact.signature_status), expected Valid." }
    if (-not $artifact.code_signing_eku) { Add-Failure $failures "$($artifact.role): Code Signing EKU $CodeSigningEkuOid is absent." }
    if ($artifact.public_key_algorithm_oid -cne $RsaOid) { Add-Failure $failures "$($artifact.role): signer is not RSA." }
    if ([int]$artifact.rsa_key_bits -lt 2048) { Add-Failure $failures "$($artifact.role): RSA key is smaller than 2048 bits." }
    if (-not $artifact.chain_build) { Add-Failure $failures "$($artifact.role): Windows certificate-chain build failed." }
    if (-not $artifact.root_present_in_windows_trust_store) { Add-Failure $failures "$($artifact.role): chain root is not present in a Windows trusted/auth root store." }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedPublisher) -and $artifact.publisher -cne $ExpectedPublisher) {
        Add-Failure $failures "$($artifact.role): publisher mismatch."
    }
    if ($expectedThumbprintNormalized -and $artifact.signer_thumbprint -cne $expectedThumbprintNormalized) {
        Add-Failure $failures "$($artifact.role): signer thumbprint mismatch."
    }
}

if ($app.signer_thumbprint -and $setup.signer_thumbprint -and $app.signer_thumbprint -cne $setup.signer_thumbprint) {
    Add-Failure $failures 'Application and Setup were not signed by the same governed certificate.'
}

if ($RequireMotw -or $RequirePublicReady) {
    if (-not $motw.present) { Add-Failure $failures 'Setup Mark-of-the-Web Zone.Identifier is absent.' }
    elseif ($motw.zone_id -ne 3) { Add-Failure $failures "Setup Mark-of-the-Web ZoneId is $($motw.zone_id), expected 3." }
}

if ($RequirePublicReady) {
    if ([string]::IsNullOrWhiteSpace($ExpectedPublisher)) { Add-Failure $failures 'RequirePublicReady requires -ExpectedPublisher.' }
    if ([string]::IsNullOrWhiteSpace($ExpectedThumbprint)) { Add-Failure $failures 'RequirePublicReady requires -ExpectedThumbprint.' }
    if ([string]::IsNullOrWhiteSpace($MicrosoftTrustedRootProgramReference)) {
        Add-Failure $failures 'RequirePublicReady requires retained Microsoft Trusted Root Program evidence reference; local root-store presence alone is insufficient.'
    }
    if (-not $defender.available) { Add-Failure $failures 'Microsoft Defender status is unavailable.' }
    else {
        if (-not $defender.antimalware_service_enabled) { Add-Failure $failures 'Microsoft Defender antimalware service is disabled.' }
        if (-not $defender.realtime_protection_enabled) { Add-Failure $failures 'Microsoft Defender real-time protection is disabled.' }
        if ($defender.related_detection_count -gt 0) { Add-Failure $failures "Microsoft Defender has $($defender.related_detection_count) related detection(s)." }
    }
    if ($SmartScreenOutcome -eq 'NotTested') { Add-Failure $failures 'SmartScreen outcome was not tested/recorded.' }
    if ($SmartScreenOutcome -in @('UnrecognizedAppUnknownPublisher', 'Blocked')) { Add-Failure $failures "SmartScreen outcome is not public-ready: $SmartScreenOutcome." }
    if ($SmartAppControlState -eq 'Enforced' -and $SmartAppControlLaunch -ne 'Allowed') {
        Add-Failure $failures "Smart App Control is enforced but launch outcome is $SmartAppControlLaunch, expected Allowed."
    }
}

if ($RequireNoSmartScreenWarning -and $SmartScreenOutcome -ne 'NoWarning') {
    Add-Failure $failures "No-warning acceptance requires SmartScreenOutcome=NoWarning, got $SmartScreenOutcome."
}

$signatureProfileReady = @($app, $setup) | Where-Object {
    $_.signature_status -ne 'Valid' -or -not $_.code_signing_eku -or $_.public_key_algorithm_oid -ne $RsaOid -or $_.rsa_key_bits -lt 2048 -or -not $_.chain_build
}

$classification = 'PUBLIC_SIGNATURE_READY_PHYSICAL_ACCEPTANCE_PENDING'
if (@($signatureProfileReady).Count -gt 0) {
    $classification = 'BLOCKED_NO_WINDOWS_PUBLIC_SIGNATURE'
} elseif ($SmartScreenOutcome -in @('UnrecognizedAppUnknownPublisher', 'Blocked') -or ($SmartAppControlState -eq 'Enforced' -and $SmartAppControlLaunch -eq 'Blocked')) {
    $classification = 'BLOCKED_USER_FACING_TRUST'
} elseif ($SmartScreenOutcome -eq 'UnrecognizedAppVerifiedPublisher') {
    $classification = 'PUBLIC_SIGNATURE_READY_REPUTATION_PENDING'
} elseif ($SmartScreenOutcome -eq 'NoWarning' -and ($SmartAppControlState -ne 'Enforced' -or $SmartAppControlLaunch -eq 'Allowed')) {
    $classification = 'PUBLIC_TRUST_ESTABLISHED_ON_TEST_HOST'
}

$evidence = [ordered]@{
    schema = 'arvectum.proxy.windows-public-trust.v1'
    task = 'APL-REL-016'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    product = 'Arvectum Proxy Launcher'
    company = 'ООО «Арвектум»'
    application = $app
    setup = $setup
    mark_of_the_web = $motw
    defender = $defender
    microsoft_trusted_root_program_reference = $MicrosoftTrustedRootProgramReference
    microsoft_trusted_root_program_membership_inferred_from_local_store = $false
    smartscreen = [ordered]@{
        outcome = $SmartScreenOutcome
        operator_recorded = ($SmartScreenOutcome -ne 'NotTested')
        valid_signature_is_not_treated_as_reputation = $true
    }
    smart_app_control = [ordered]@{
        state = $SmartAppControlState
        exact_candidate_launch = $SmartAppControlLaunch
    }
    expected_identity = [ordered]@{
        publisher = $ExpectedPublisher
        signer_thumbprint = $expectedThumbprintNormalized
    }
    classification = $classification
    require_motw = [bool]$RequireMotw
    require_public_ready = [bool]$RequirePublicReady
    require_no_smartscreen_warning = [bool]$RequireNoSmartScreenWarning
    result = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    failures = @($failures)
}

$outputParent = Split-Path -Parent $OutputPath
if ($outputParent -and -not (Test-Path -LiteralPath $outputParent)) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
}
$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8

Write-Host "APL-REL-016 evidence: $OutputPath"
Write-Host "APL-REL-016 classification: $classification"
Write-Host "APL-REL-016 result: $($evidence.result)"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL: $_" }
    throw "APL-REL-016 public trust gate failed with $($failures.Count) failure(s)."
}
