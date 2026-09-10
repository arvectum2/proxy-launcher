import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
PREPARE = ROOT / "tools" / "windows_app_control_prepare_final_stand.ps1"
RUN = ROOT / "tools" / "windows_app_control_run_final_stand.ps1"

BASE_POLICY_ID = "dc1c604c-46ea-40b7-9f47-cf582b225d5e"
SETUP_SHA256 = "5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414"
APP_SHA256 = "f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a"
RUNTIME_SHA256 = "b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_stand_wrappers_are_ascii_safe_for_windows_powershell_51():
    for path in (PREPARE, RUN):
        assert all(byte < 128 for byte in path.read_bytes()), path


def test_prepare_is_bound_to_canonical_lab_base_and_exact_release_identities():
    body = text(PREPARE)
    for expected in (BASE_POLICY_ID, SETUP_SHA256, APP_SHA256, RUNTIME_SHA256):
        assert expected in body
    assert "arvectum2/proxy-launcher" in body
    assert "source_commit" in body
    assert "result = 'PREPARED'" in body


def test_prepare_requires_clean_canonical_git_checkout_for_source_provenance():
    body = text(PREPARE)
    for expected in (
        "git -C $RepositoryRoot rev-parse HEAD",
        "git -C $RepositoryRoot remote get-url origin",
        "arvectum2/proxy-launcher",
        "git -C $RepositoryRoot status --porcelain=v1 --untracked-files=all",
        "Repository working tree is dirty; final stand evidence requires an exact clean checkout.",
        "source_remote = $sourceRemote",
        "source_worktree_clean = $true",
    ):
        assert expected in body


def test_prepare_orders_historical_recovery_before_both_trust_packs():
    body = text(PREPARE)
    recovery = body.index("windows_app_control_recover_0_2_2_baseline.ps1")
    baseline = body.index("windows_app_control_legacy_baseline_trust_pack.ps1")
    current = body.index("windows_app_control_prepare_production_runtime_trust.ps1")
    runtime_verify = body.index("windows_app_control_verify_runtime_trust_pack.ps1")
    assert recovery < baseline < current < runtime_verify
    assert "ReferenceFullHash" in body
    assert "apl-win-014-0.2.2-baseline-recovery.json" in body


def test_prepare_seals_both_generated_policy_ids_and_cips_for_handoff():
    body = text(PREPARE)
    for expected in (
        "stand-state.json",
        "POLICIES_TO_DEPLOY.txt",
        "baseline = [ordered]@{",
        "current = [ordered]@{",
        "supplemental_policy_id = $baselinePolicyId.ToString('D')",
        "supplemental_policy_id = $currentPolicyId.ToString('D')",
        "supplemental_policy_cip_sha256",
        "policy_deployment = 'NOT PERFORMED'",
        "security_controls_modified = $false",
        "product_lifecycle_modified = $false",
    ):
        assert expected in body
    assert "Baseline supplemental PolicyID" in body
    assert "Current supplemental PolicyID" in body


def test_prepare_never_deploys_removes_or_weakens_app_control():
    lowered = text(PREPARE).lower()
    for forbidden in (
        "--update-policy",
        "--remove-policy",
        "set-ruleoption",
        "set-itemproperty",
        "remove-itemproperty",
        "verifiedandreputablepolicystate",
        "disable-windowsoptionalfeature",
    ):
        assert forbidden not in lowered
    assert "policy deployment: not performed" in lowered
    assert "security controls modified: no" in lowered


def test_run_requires_isolation_and_documented_active_policy_state_before_cleanup():
    body = text(RUN)
    main_isolation = body.index("if (-not $IsolatedAcceptanceEnvironment)")
    active_check = body.index("Assert-PreparedPoliciesActive -Policies $policies")
    identity_check = body.index("$reference = Assert-ExactReferenceTree")
    cleanup = body.index("Clean-ExactCurrentReference -InstalledRoot")
    final_gate = body.index("& $finalGate @gateArgs")
    assert main_isolation < active_check < identity_check < cleanup < final_gate
    assert "is_authorized" in body
    assert "is_on_disk" in body
    assert "is_enforced" in body
    assert "supplemental policy is not active/enforced/on-disk" in body
    assert "policy_options" not in body
    assert "PolicyOptions" not in body


def test_run_guid_normalization_tolerates_empty_citool_base_policy_ids():
    body = text(RUN)
    assert "if ($null -eq $Value) { return '' }" in body
    assert "$text = ([string]$Value).Trim().Trim('{}')" in body
    assert "[string]::IsNullOrWhiteSpace($text)" in body
    assert "catch { return $text.ToLowerInvariant() }" in body


def test_run_reverifies_complete_reference_inventory_and_exact_lifecycle_bytes():
    body = text(RUN)
    assert "reference_files" in body
    assert "Live reference installation file count drifted" in body
    assert "Live reference installation contains an unverified file" in body
    assert "Live reference installation changed after trust-pack authoring" in body
    assert "Arvectum Proxy Launcher.exe" in body
    assert "Arvectum Proxy Launcher Repair.exe" in body
    assert "unins000.exe" in body
    assert SETUP_SHA256 in body
    assert APP_SHA256 in body
    assert RUNTIME_SHA256 in body


def test_run_cleanup_is_narrow_and_fail_closed():
    body = text(RUN)
    assert "canonical Documents\\ArvectumProxyLauncher reference root" in body
    assert "Arvectum\\ProxyLauncher" in body
    assert "Uninstaller left an unknown file; refusing cleanup" in body
    assert "Uninstaller left a changed file; refusing cleanup" in body
    assert "Remove-Item -LiteralPath $InstalledRoot -Recurse -Force" in body
    assert "Remove-Item -LiteralPath $stateRoot -Recurse -Force" in body
    assert "--rollback" in body
    assert "WaitForExit(20000)" in body
    assert "Get-ExactLauncherProcesses" in body
    assert "TCP 8082 remains occupied" in body
    assert "Remove-Item -Path *" not in body
    assert "Remove-Item *" not in body


def test_run_invokes_only_canonical_final_gate_and_never_manages_policy():
    body = text(RUN)
    lowered = body.lower()
    assert "windows_app_control_local_gate_complete.ps1" in body
    assert "windows_app_control_upgrade_acceptance.ps1" not in body
    assert "windows_app_control_enforced_acceptance.ps1" not in body
    for forbidden in (
        "--update-policy",
        "--remove-policy",
        "set-ruleoption",
        "set-cipolicy",
        "convertfrom-cipolicy",
        "new-cipolicy",
        "verifiedandreputablepolicystate",
    ):
        assert forbidden not in lowered
    assert "Policy deployment/removal by this wrapper: NONE" in body
    assert "Security-control weakening by this wrapper: NONE" in body


def test_run_requires_all_canonical_final_subgates_to_pass():
    body = text(RUN)
    for expected in (
        "apl-win-014-final-result.json",
        "runtime_trust_gate",
        "upgrade_gate",
        "current_release_gate",
        "Canonical final evidence is not an all-subgate PASS.",
    ):
        assert expected in body


def test_powershell_parser_accepts_new_wrappers_on_windows():
    if os.name != "nt":
        return
    for path in (PREPARE, RUN):
        escaped = str(path).replace("'", "''")
        command = (
            "$ErrorActionPreference='Stop'; "
            "$text=Get-Content -LiteralPath '" + escaped + "' -Raw; "
            "[void][scriptblock]::Create($text)"
        )
        completed = subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command", command],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert completed.returncode == 0, completed.stderr or completed.stdout
