from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "tools" / "windows_app_control_enterprise_trust_pack.ps1"
RUNTIME_PREP = ROOT / "tools" / "windows_app_control_prepare_production_runtime_trust.ps1"
FINAL_PREP = ROOT / "tools" / "windows_app_control_prepare_final_stand.ps1"
RUNBOOK = ROOT / "docs" / "APL_WIN_014_FINAL_STAND_RUNBOOK.md"

UPGRADE_HELPER_SHA256 = "77e8bcb4d27aad5b2d1b40753f3ec2dfa2419e48a07f2eb17a7b15f2a9232218"
UNINSTALL_HELPER_SHA256 = "7abc1fe332975440d2c84be608773a890c5bb4deb130eea54378a128e79b0a44"
RELEASE_POLICY_COMMIT = "47823585c42da54ab51dc2246583dc24d74d4ba6"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_enterprise_pack_requires_explicit_sealed_maintenance_source_root():
    body = text(PACK)
    assert "[Parameter(Mandatory = $true)] [string]$MaintenanceSourceRoot" in body
    assert "$MaintenanceSourceRoot = (Resolve-Path -LiteralPath $MaintenanceSourceRoot).Path" in body
    assert "Join-Path $MaintenanceSourceRoot 'upgrade_helper.ps1'" in body
    assert "Join-Path $MaintenanceSourceRoot 'uninstall_helper.ps1'" in body
    assert UPGRADE_HELPER_SHA256 in body
    assert UNINSTALL_HELPER_SHA256 in body
    assert RELEASE_POLICY_COMMIT in body
    assert "SEALED_RELEASE_SOURCE_EXACT_HASH" in body


def test_portable_archive_is_not_used_as_maintenance_helper_source():
    body = text(PACK)
    portable_extract_section = body[body.index("Expand-Archive -LiteralPath $portable"):]
    assert "Get-OnePortableFile -Root $portableExtract -Name 'Arvectum Proxy Launcher.exe'" in portable_extract_section
    assert "Get-OnePortableFile -Root $portableExtract -Name 'upgrade_helper.ps1'" not in body
    assert "Get-OnePortableFile -Root $portableExtract -Name 'uninstall_helper.ps1'" not in body
    assert "Get-OnePortableFile -Root $portableExtract -Name 'build_manifest.json'" not in body
    assert "production portable ZIP is\nnot treated as a source for installer maintenance helpers" in body


def test_runtime_authoring_requires_and_forwards_maintenance_source_root():
    body = text(RUNTIME_PREP)
    assert "[Parameter(Mandatory = $true)] [string]$MaintenanceSourceRoot" in body
    assert "$MaintenanceSourceRoot = (Resolve-Path -LiteralPath $MaintenanceSourceRoot).Path" in body
    assert UPGRADE_HELPER_SHA256 in body
    assert UNINSTALL_HELPER_SHA256 in body
    assert "-MaintenanceSourceRoot $MaintenanceSourceRoot" in body
    assert "maintenance_source_root = $MaintenanceSourceRoot" in body


def test_final_stand_requires_forwards_and_seals_maintenance_source_root():
    body = text(FINAL_PREP)
    assert "[Parameter(Mandatory = $true)] [string]$MaintenanceSourceRoot" in body
    assert "$MaintenanceSourceRoot = (Resolve-Path -LiteralPath $MaintenanceSourceRoot).Path" in body
    assert "-MaintenanceSourceRoot $MaintenanceSourceRoot" in body
    assert "maintenance_source_root = $MaintenanceSourceRoot" in body
    assert "maintenance_source_contract = 'SEALED_RELEASE_SOURCE_EXACT_HASH'" in body
    assert UPGRADE_HELPER_SHA256 in body
    assert UNINSTALL_HELPER_SHA256 in body


def test_runbook_requires_exact_release_source_maintenance_helpers():
    body = text(RUNBOOK)
    lower = body.lower()
    assert "maintenancesourceroot" in lower
    assert "upgrade_helper.ps1" in body
    assert "uninstall_helper.ps1" in body
    assert UPGRADE_HELPER_SHA256 in lower
    assert UNINSTALL_HELPER_SHA256 in lower
    assert RELEASE_POLICY_COMMIT in lower
    assert "portable zip" in lower
    assert "not" in lower
