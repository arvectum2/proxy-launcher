<# Build one final APL-WIN-014 0.2.4 candidate and self-contained physical test kit on Windows CI. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$CandidateSourceCommit,
    [Parameter(Mandatory)] [string]$CandidateOutputDirectory,
    [string]$PythonExecutable = 'python',
    [string]$IsccPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Final 0.2.4 candidate build must run on Windows.' }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root
$head = (git rev-parse HEAD).Trim()
if ($head -cne $CandidateSourceCommit) { throw "HEAD $head does not match candidate source $CandidateSourceCommit." }
if (git status --porcelain) { throw 'Candidate source checkout is not clean.' }

function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-FileIdentity([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    return [ordered]@{ filename = $item.Name; size = [long]$item.Length; sha256 = Get-Sha256 $item.FullName }
}
function Require-Pass([object]$Value, [string]$Name) {
    if ([string]$Value -ne 'PASS') { throw "$Name did not report PASS: $Value" }
}

$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if ($version -ne '0.2.4') { throw "Final APL-WIN-014 candidate must be version 0.2.4; got $version." }
$predecessorVersion = '0.2.3'

# 1. Build the application exactly once. All release surfaces consume these frozen bytes.
& (Join-Path $root 'tools\clean_build_windows.ps1') -PythonExecutable $PythonExecutable
if ($LASTEXITCODE -ne 0) { throw 'Canonical Windows application build failed.' }

$app = Join-Path $root 'dist\Arvectum Proxy Launcher.exe'
$portable = Join-Path $root "out\Arvectum-Proxy-Launcher-$version-windows-x64-portable.zip"
$buildResult = Join-Path $root 'out\build-result.json'
foreach ($path in @($app,$portable,$buildResult)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Single-build output missing: $path" }
}
& (Join-Path $root 'tools\windows_promoted_license_compliance.ps1') -PortableZip $portable
if ($LASTEXITCODE -ne 0) { throw 'Portable license compliance failed.' }

$frozenApplication = Get-FileIdentity $app
$portableIdentity = Get-FileIdentity $portable
$portableResult = Get-Content -LiteralPath $buildResult -Raw | ConvertFrom-Json
if ([string]$portableResult.source_commit -cne $head) { throw 'Portable build-result source commit mismatch.' }
if ([string]$portableResult.exe_sha256 -cne $frozenApplication.sha256) { throw 'Portable build-result application SHA256 mismatch.' }

# 2. Build a synthetic 0.2.3 predecessor only for CI upgrade proof.
& (Join-Path $root 'tools\build_windows_installer.ps1') `
    -UseExistingPayload `
    -ApplicationExe $app `
    -PortableZip $portable `
    -BuildResultPath $buildResult `
    -ExpectedApplicationSha256 $frozenApplication.sha256 `
    -IsccPath $IsccPath `
    -SyntheticPredecessor
if ($LASTEXITCODE -ne 0) { throw 'Synthetic 0.2.3 predecessor compilation failed.' }
$predecessor = @(Get-ChildItem -LiteralPath (Join-Path $root 'out\installer') -Filter '*-synthetic-predecessor.exe' -File | Select-Object -First 1)
if ($predecessor.Count -ne 1) { throw 'Synthetic predecessor Setup was not produced uniquely.' }
$predecessorPath = $predecessor[0].FullName

# 3. Build final Setup from exactly the frozen application bytes.
& (Join-Path $root 'tools\build_windows_installer.ps1') `
    -UseExistingPayload `
    -ApplicationExe $app `
    -PortableZip $portable `
    -BuildResultPath $buildResult `
    -ExpectedApplicationSha256 $frozenApplication.sha256 `
    -IsccPath $IsccPath
if ($LASTEXITCODE -ne 0) { throw 'Final 0.2.4 Setup compilation failed.' }

$setup = Join-Path $root "out\installer\Arvectum-Proxy-Launcher-$version-windows-x64-setup.exe"
$installerManifest = Join-Path $root 'out\installer-payload\build_manifest.json'
foreach ($path in @($setup,$installerManifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Final Setup output missing: $path" }
}

# 4. Reuse the established Windows lifecycle suites. With VERSION=0.2.4, the synthetic predecessor is 0.2.3.
$issue171Evidence = Join-Path $root 'out\windows-installer-171-e2e.json'
& (Join-Path $root 'qa\windows_installer_171_e2e.ps1') -CurrentSetup $setup -CurrentPortableExe $app -CurrentVersion $version -EvidencePath $issue171Evidence
if ($LASTEXITCODE -ne 0) { throw 'Installer #171 E2E failed.' }

$rcEvidence = Join-Path $root 'out\windows-rc-e2e.json'
& (Join-Path $root 'qa\windows_rc_e2e.ps1') -CurrentSetup $setup -PredecessorSetup $predecessorPath -CurrentVersion $version -EvidencePath $rcEvidence
if ($LASTEXITCODE -ne 0) { throw 'Windows RC lifecycle E2E failed.' }

$acceptance = Join-Path $root 'out\windows-rc-acceptance.json'
& (Join-Path $root 'tools\windows_rc_acceptance.ps1') -PortableZip $portable -SetupExe $setup -LifecycleEvidence $rcEvidence -OutputPath $acceptance
if ($LASTEXITCODE -ne 0) { throw 'Windows RC acceptance failed.' }

$installerEvidence = Get-Content -LiteralPath $issue171Evidence -Raw | ConvertFrom-Json
$rc = Get-Content -LiteralPath $rcEvidence -Raw | ConvertFrom-Json
$acceptanceEvidence = Get-Content -LiteralPath $acceptance -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $installerManifest -Raw | ConvertFrom-Json
$installedHash = ([string]$installerEvidence.final_application_sha256).ToLowerInvariant()
if ($installedHash -ne $frozenApplication.sha256) { throw 'Installed application does not equal the single frozen application build.' }
if ([string]$manifest.version -ne $version) { throw 'Installer manifest version mismatch.' }
if (([string]$manifest.application_sha256).ToLowerInvariant() -ne $frozenApplication.sha256) { throw 'Installer manifest application SHA256 does not equal frozen application.' }
if (([string]$installerEvidence.current_setup_sha256).ToLowerInvariant() -ne (Get-Sha256 $setup)) { throw 'Installer E2E did not consume final Setup.' }
if (([string]$rc.current_setup_sha256).ToLowerInvariant() -ne (Get-Sha256 $setup)) { throw 'RC E2E did not consume final Setup.' }
Require-Pass $installerEvidence.result 'Installer #171 E2E'
Require-Pass $rc.result 'Windows RC E2E'
Require-Pass $acceptanceEvidence.result 'Windows RC acceptance'
if ([string]$rc.phases.upgrade -ne 'PASS') { throw '0.2.3 -> 0.2.4 CI upgrade gate did not PASS.' }
if ([string]$rc.phases.fresh_install_smoke -ne 'PASS') { throw 'Fresh install gate did not PASS.' }
if ([string]$rc.phases.repair -ne 'PASS') { throw 'Repair gate did not PASS.' }
if ([string]$rc.phases.uninstall -ne 'PASS') { throw 'Uninstall gate did not PASS.' }

# 5. Capture the deterministic uninstaller from the same Setup so physical App Control can authorize it before lifecycle execution.
$documentsRoot = [Environment]::GetFolderPath('MyDocuments')
$referenceRoot = Join-Path $documentsRoot 'ArvectumProxyLauncher'
if (Test-Path -LiteralPath $referenceRoot) { throw "CI reference install root is not clean: $referenceRoot" }
$refLog = Join-Path $root 'out\final-0.2.4-reference-install.log'
$installProcess = Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',("/LOG=$refLog")) -PassThru -Wait
if ($installProcess.ExitCode -ne 0) { throw "Reference install failed with exit code $($installProcess.ExitCode)." }
$referenceApp = Join-Path $referenceRoot 'Arvectum Proxy Launcher.exe'
$referenceRepair = Join-Path $referenceRoot 'Arvectum Proxy Launcher Repair.exe'
$referenceUninstaller = Join-Path $referenceRoot 'unins000.exe'
foreach ($path in @($referenceApp,$referenceRepair,$referenceUninstaller)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Reference lifecycle file missing: $path" }
}
if ((Get-Sha256 $referenceApp) -ne $frozenApplication.sha256) { throw 'Reference installed EXE differs from frozen application.' }
if ((Get-Sha256 $referenceRepair) -ne (Get-Sha256 $setup)) { throw 'Reference Repair Setup differs from final Setup.' }
$uninstallerIdentity = Get-FileIdentity $referenceUninstaller

$output = [IO.Path]::GetFullPath($CandidateOutputDirectory)
if (Test-Path -LiteralPath $output) { throw "Candidate output directory already exists: $output" }
New-Item -ItemType Directory -Path $output | Out-Null
$policyMaterial = Join-Path $output 'policy-material'
New-Item -ItemType Directory -Path $policyMaterial | Out-Null
Copy-Item -LiteralPath $referenceUninstaller -Destination (Join-Path $policyMaterial 'unins000.exe')

$uninstallLog = Join-Path $root 'out\final-0.2.4-reference-uninstall.log'
$uninstallProcess = Start-Process -FilePath $referenceUninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/LOG=$uninstallLog")) -PassThru -Wait
if ($uninstallProcess.ExitCode -ne 0) { throw "Reference uninstall failed with exit code $($uninstallProcess.ExitCode)." }
Start-Sleep -Seconds 1
if (Test-Path -LiteralPath $referenceApp -PathType Leaf) { throw 'Reference application remains after uninstall.' }

# 6. Assemble exactly one physical-test artifact. Synthetic predecessor is evidence-only and is deliberately not shipped.
$setupIdentity = Get-FileIdentity $setup
$manifestIdentity = Get-FileIdentity $installerManifest
$upgradeIdentity = Get-FileIdentity (Join-Path $root 'installer\upgrade_helper.ps1')
$uninstallHelperIdentity = Get-FileIdentity (Join-Path $root 'installer\uninstall_helper.ps1')
$runnerPath = Join-Path $root 'tools\apl_win_014_final_0_2_4_physical.ps1'
$runnerIdentity = Get-FileIdentity $runnerPath
$runId = if ($env:GITHUB_RUN_ID) { $env:GITHUB_RUN_ID } else { 'local-not-publishable' }
$attempt = if ($env:GITHUB_RUN_ATTEMPT) { $env:GITHUB_RUN_ATTEMPT } else { '0' }

$evidence = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-final-0.2.4-candidate.v1'
    task = 'APL-WIN-014'
    product_version = $version
    supported_predecessor_version = $predecessorVersion
    candidate_source_commit = $head
    github_run_id = $runId
    github_run_attempt = $attempt
    application = $frozenApplication
    setup = $setupIdentity
    portable_zip = $portableIdentity
    build_manifest = $manifestIdentity
    upgrade_helper = $upgradeIdentity
    uninstall_helper = $uninstallHelperIdentity
    reference_uninstaller = $uninstallerIdentity
    physical_runner = $runnerIdentity
    runtime_trust = [ordered]@{
        inno_version = '6.7.1'
        exact_runtime_sha256 = 'b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8'
        stand_expected_path = 'C:\Arvectum\Evidence\APL-WIN-014\reference-bootstrap-final\runtime\inno-setup-6.7.1-runtime-stub.exe'
    }
    checks = [ordered]@{
        single_application_build = 'PASS'
        portable_application_identity = 'PASS'
        setup_installed_application_identity = 'PASS'
        synthetic_predecessor_version = $predecessorVersion
        ci_upgrade_0_2_3_to_0_2_4 = [string]$rc.phases.upgrade
        fresh_install = [string]$rc.phases.fresh_install_smoke
        repair = [string]$rc.phases.repair
        uninstall = [string]$rc.phases.uninstall
        windows_rc_acceptance = [string]$acceptanceEvidence.result
        physical_enforced_app_control = 'PENDING'
    }
}
$evidencePath = Join-Path $output 'candidate_evidence.json'
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding utf8

Copy-Item -LiteralPath $setup -Destination $output
Copy-Item -LiteralPath $app -Destination $output
Copy-Item -LiteralPath $portable -Destination $output
Copy-Item -LiteralPath $installerManifest -Destination $output
Copy-Item -LiteralPath (Join-Path $root 'installer\upgrade_helper.ps1') -Destination $output
Copy-Item -LiteralPath (Join-Path $root 'installer\uninstall_helper.ps1') -Destination $output
Copy-Item -LiteralPath $runnerPath -Destination $output
Copy-Item -LiteralPath $issue171Evidence,$rcEvidence,$acceptance,$refLog -Destination $output

$contract = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-final-0.2.4-physical-contract.v1'
    task = 'APL-WIN-014'
    base_policy_id = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
    predecessor = [ordered]@{
        version = '0.2.3'
        setup_sha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
        application_sha256 = 'f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a'
    }
    candidate = [ordered]@{
        version = '0.2.4'
        setup_sha256 = $setupIdentity.sha256
        application_sha256 = $frozenApplication.sha256
        portable_sha256 = $portableIdentity.sha256
        uninstaller_sha256 = $uninstallerIdentity.sha256
        runner_sha256 = $runnerIdentity.sha256
    }
    inno_runtime_sha256 = 'b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8'
    remaining_physical_gates = @('upgrade_0.2.3_to_0.2.4','runtime_pac_wininet','rollback','repair','uninstall','zero_arvectum_3077','app_control_remains_enforced')
}
$contract | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'physical_test_contract.json') -Encoding utf8

$sums = Get-ChildItem -LiteralPath $output -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($output.Length).TrimStart('\')
    "$(Get-Sha256 $_.FullName)  $relative"
}
Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Value $sums -Encoding ascii

Write-Host "APL-WIN-014 final 0.2.4 candidate PASS: $output"
Write-Host "Setup SHA256: $($setupIdentity.sha256)"
Write-Host "Application SHA256: $($frozenApplication.sha256)"
Write-Host "Uninstaller SHA256: $($uninstallerIdentity.sha256)"
