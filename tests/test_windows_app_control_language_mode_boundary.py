from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
DOCS = ROOT / "docs"


def read_tool(name: str) -> str:
    return (TOOLS / name).read_text(encoding="utf-8")


def test_runtime_material_validator_has_standalone_json_contract() -> None:
    text = read_tool("windows_app_control_inno_runtime_material.ps1")

    assert "[switch]$AsJson" in text
    assert "Get-ArvectumInnoRuntimeMaterial" in text
    assert "ConvertTo-Json" in text
    assert "-Compress" in text
    assert "Standalone runtime validation requires" in text


def test_canonical_consumers_do_not_dot_source_or_use_powershell_file_for_trusted_children() -> None:
    enterprise = read_tool("windows_app_control_enterprise_trust_pack.ps1")
    prepare = read_tool("windows_app_control_prepare_production_runtime_trust.ps1")
    final_gate = read_tool("windows_app_control_local_gate_complete.ps1")

    assert ". $runtimeHelper" not in enterprise
    assert ". $validator" not in prepare

    assert "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Verifier" not in enterprise
    assert "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Validator" not in enterprise
    assert "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validator" not in prepare
    assert "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtimeTrustVerifier" not in final_gate

    assert "& $Verifier -ReleaseDirectory $Directory" in enterprise
    assert "& $Validator" in enterprise
    assert "& $validator" in prepare
    assert "& $runtimeTrustVerifier -TrustPackDirectory $TrustPackDirectory" in final_gate

    assert "-AsJson" in enterprise
    assert "-AsJson" in prepare
    assert "ConvertFrom-Json" in enterprise
    assert "ConvertFrom-Json" in prepare


def test_language_mode_fix_does_not_weaken_app_control_contract() -> None:
    enterprise = read_tool("windows_app_control_enterprise_trust_pack.ps1")
    prepare = read_tool("windows_app_control_prepare_production_runtime_trust.ps1")

    assert "Disabled:Script Enforcement" in enterprise
    assert "script_enforcement_preserved = $true" in enterprise
    assert "CiTool" not in enterprise.replace("Do not run CiTool --update-policy from this generator.", "")

    assert "CiTool" not in prepare
    assert "security_controls_modified = $false" in prepare
    assert "policy_deployed = $false" in prepare


def test_final_stand_user_instructions_do_not_reintroduce_powershell_file() -> None:
    prepare_final = read_tool("windows_app_control_prepare_final_stand.ps1")
    runbook = (DOCS / "APL_WIN_014_FINAL_STAND_RUNBOOK.md").read_text(encoding="utf-8")

    assert "powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\\windows_app_control_run_final_stand.ps1" not in prepare_final
    assert "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\\tools\\windows_app_control_prepare_final_stand.ps1" not in runbook
    assert "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\\tools\\windows_app_control_run_final_stand.ps1" not in runbook
    assert "& .\\tools\\windows_app_control_prepare_final_stand.ps1" in runbook
    assert "& .\\tools\\windows_app_control_run_final_stand.ps1 -IsolatedAcceptanceEnvironment" in runbook
