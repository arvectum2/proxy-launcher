from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"


def read_tool(name: str) -> str:
    return (TOOLS / name).read_text(encoding="utf-8")


def test_runtime_material_validator_has_standalone_json_contract() -> None:
    text = read_tool("windows_app_control_inno_runtime_material.ps1")

    assert "[switch]$AsJson" in text
    assert "Get-ArvectumInnoRuntimeMaterial" in text
    assert "ConvertTo-Json" in text
    assert "-Compress" in text
    assert "Standalone runtime validation requires" in text


def test_canonical_consumers_do_not_dot_source_runtime_validator() -> None:
    enterprise = read_tool("windows_app_control_enterprise_trust_pack.ps1")
    prepare = read_tool("windows_app_control_prepare_production_runtime_trust.ps1")

    assert ". $runtimeHelper" not in enterprise
    assert ". $validator" not in prepare

    assert "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Validator" in enterprise
    assert "-AsJson" in enterprise
    assert "ConvertFrom-Json" in enterprise
    assert "Inno runtime validation process failed" in enterprise

    assert "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validator" in prepare
    assert "-AsJson" in prepare
    assert "ConvertFrom-Json" in prepare
    assert "Inno runtime validation process failed" in prepare


def test_language_mode_fix_does_not_weaken_app_control_contract() -> None:
    enterprise = read_tool("windows_app_control_enterprise_trust_pack.ps1")
    prepare = read_tool("windows_app_control_prepare_production_runtime_trust.ps1")

    assert "Disabled:Script Enforcement" in enterprise
    assert "script_enforcement_preserved = $true" in enterprise
    assert "CiTool" not in enterprise.replace("Do not run CiTool --update-policy from this generator.", "")

    assert "CiTool" not in prepare
    assert "security_controls_modified = $false" in prepare
    assert "policy_deployed = $false" in prepare
