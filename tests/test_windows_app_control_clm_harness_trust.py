from pathlib import Path
import os
import subprocess


ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "tools" / "windows_app_control_prepare_harness_script_trust_clm.ps1"
PROBE = ROOT / "tools" / "windows_app_control_harness_language_probe.ps1"

BASE_POLICY_ID = "dc1c604c-46ea-40b7-9f47-cf582b225d5e"
PRODUCTION_SETUP_SHA256 = "5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_clm_bootstrap_is_bound_to_canonical_base_and_production_setup():
    body = text(BOOTSTRAP)
    assert BASE_POLICY_ID in body
    assert PRODUCTION_SETUP_SHA256 in body
    assert "Arvectum APL-WIN-014 Lab Base" in body
    assert "Enabled:Audit Mode" in body
    assert "Enabled:Allow Supplemental Policies" in body


def test_clm_bootstrap_has_no_full_language_only_entry_guards_or_known_forbidden_methods():
    body = text(BOOTSTRAP)
    forbidden = (
        "#Requires",
        "[Environment]::",
        "[System.Environment]::",
        "[IO.Path]::",
        "[System.IO.Path]::",
        "New-Object",
        ".WaitForExit(",
        ".ToLowerInvariant(",
        ".Trim(",
        ".Substring(",
        "[Guid]",
        "[DateTime]::",
        "[Security.Principal",
        "[System.Security.Principal",
    )
    for token in forbidden:
        assert token not in body, token


def test_clm_bootstrap_authors_script_rules_without_trusting_a_general_interpreter():
    body = text(BOOTSTRAP)
    policy_line = next(line for line in body.splitlines() if line.strip().startswith("New-CIPolicy "))
    assert "-Level Hash" in policy_line
    assert "-NoScript" not in policy_line
    assert "script-scan-root" in body
    assert "verify_russian_release.ps1" in body
    assert "python_authorized=$false" in body
    assert "general_interpreter_authorized=$false" in body
    assert "Copy-Item -LiteralPath $source -Destination $destination" in body
    assert "Copy-Item -LiteralPath $releaseVerifier -Destination $releaseVerifierStaged" in body


def test_clm_bootstrap_never_deploys_removes_or_weakens_policy():
    body = text(BOOTSTRAP).lower()
    for forbidden in (
        "& $citool --update-policy",
        "start-process -filepath $citool",
        "--remove-policy",
        "set-ruleoption",
        "verifiedandreputablepolicystate",
        "reg.exe add",
        "disable-windowsoptionalfeature",
    ):
        assert forbidden not in body
    assert "policy_deployment='not performed'" in body
    assert "security_controls_weakened=$false" in body


def test_harness_trust_scope_is_exact_and_contains_only_required_powershell_entrypoints():
    body = text(BOOTSTRAP)
    required = {
        "windows_app_control_prepare_final_stand.ps1",
        "windows_app_control_run_final_stand.ps1",
        "windows_app_control_recover_0_2_2_baseline.ps1",
        "windows_app_control_legacy_baseline_trust_pack.ps1",
        "windows_app_control_prepare_production_runtime_trust.ps1",
        "windows_app_control_enterprise_trust_pack.ps1",
        "windows_app_control_inno_runtime_material.ps1",
        "windows_app_control_verify_runtime_trust_pack.ps1",
        "windows_app_control_local_gate_complete.ps1",
        "windows_app_control_enforced_acceptance.ps1",
        "windows_app_control_preverified_release.ps1",
        "windows_app_control_harness_language_probe.ps1",
    }
    for filename in required:
        assert f"'{filename}'" in body
    assert "*.ps1" not in body
    assert "-Recurse" not in body


def test_language_probe_requires_real_fulllanguage_and_uses_previous_failure_as_positive_probe():
    body = text(PROBE)
    assert "#Requires -Version 5.1" in body
    assert "#Requires -RunAsAdministrator" in body
    assert "LanguageMode" in body
    assert "FullLanguage" in body
    assert "[Environment]::GetFolderPath('MyDocuments')" in body
    assert "harness App Control script trust: PASS" in body


def test_scripts_are_ascii_safe():
    for path in (BOOTSTRAP, PROBE):
        path.read_bytes().decode("ascii")


def test_scripts_parse_with_windows_powershell_when_available():
    if os.name != "nt":
        return
    for path in (BOOTSTRAP, PROBE):
        escaped = str(path).replace("'", "''")
        command = (
            "$e=$null;$t=$null;"
            f"[void][System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$t,[ref]$e);"
            "if($e.Count){$e|ForEach-Object{Write-Error $_.Message};exit 1}"
        )
        completed = subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command", command],
            capture_output=True,
            text=True,
        )
        assert completed.returncode == 0, completed.stderr or completed.stdout
