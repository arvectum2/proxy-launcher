from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASSESS = ROOT / "tools" / "windows_app_control_assess.ps1"
PACK = ROOT / "tools" / "windows_app_control_enterprise_trust_pack.ps1"
RUNTIME = ROOT / "tools" / "windows_app_control_inno_runtime_material.ps1"
RUNTIME_VERIFY = ROOT / "tools" / "windows_app_control_verify_runtime_trust_pack.ps1"
OWNER = ROOT / "tools" / "windows_owner_source_mode.ps1"
DOC = ROOT / "docs" / "WINDOWS_APP_CONTROL_COMPATIBILITY.md"


RUNTIME_SHA256 = "b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8"
PRODUCTION_SETUP_SHA256 = "5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_powershell_scripts_are_ascii_safe_for_windows_powershell_51():
    for path in (ASSESS, PACK, RUNTIME, RUNTIME_VERIFY, OWNER):
        assert all(byte < 128 for byte in path.read_bytes()), path


def test_assessment_is_read_only_and_does_not_change_app_control_state():
    body = text(ASSESS)
    assert "VerifiedAndReputablePolicyState" in body
    assert "CiTool.exe" in body
    assert "Get-AuthenticodeSignature" in body
    for forbidden in (
        "Set-ItemProperty",
        "Remove-ItemProperty",
        "--update-policy",
        "--remove-policy",
        "Set-CIPolicy",
    ):
        assert forbidden not in body


def test_enterprise_pack_verifies_exact_russian_release_before_policy_generation():
    body = text(PACK)
    verifier = body.index("Invoke-ReleaseVerifier -Verifier $verifier -Directory $ReleaseDirectory")
    policy = body.index("New-CIPolicy -MultiplePolicyFormat")
    assert verifier < policy
    assert PRODUCTION_SETUP_SHA256 in body
    assert "62d313547b4d8c2c8e6951d6cd866bb954fdf199ad7650063c8ed3bfbc455801" in body
    assert "f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a" in body
    assert "EE1CFA955BA22F03C39C76B183D94CD37494582E" in body


def test_enterprise_pack_generates_supplemental_exact_hash_policy_only():
    body = text(PACK)
    assert "[Guid]$BasePolicyId" in body
    assert "-Level Hash" in body
    assert "-MultiplePolicyFormat" in body
    assert "-SupplementsBasePolicyID $BasePolicyId" in body
    assert "ConvertFrom-CIPolicy" in body
    assert "ReferenceFullHash" in body
    assert "BootstrapHash" in body


def test_enterprise_pack_binds_exact_inno_child_runtime_before_policy_authoring():
    body = text(PACK)
    helper = text(RUNTIME)
    validate = body.index("Get-ArvectumInnoRuntimeMaterial")
    policy = body.index("New-CIPolicy -MultiplePolicyFormat")
    assert validate < policy
    assert "windows_app_control_inno_runtime_material.ps1" in body
    assert "inno-setup-6.7.1-runtime-stub.exe" in body
    assert "hash_policy_integrated = $true" in body
    assert "evidence_workflow_run = $runtime.evidence_workflow_run" in body
    assert "behavioral_workflow_run = $runtime.behavioral_workflow_run" in body
    assert "historical_anchor_setup_sha256 = $runtime.historical_anchor_setup_sha256" in body
    assert RUNTIME_SHA256 in helper
    assert PRODUCTION_SETUP_SHA256 not in helper  # exact production hash is passed by the canonical pack
    assert "33669452947" in helper  # independent static evidence workflow
    assert "33666343748" in helper  # behavioral extraction workflow
    assert "is-6_7_1" in helper
    assert "cfdf48923178df4b4f040e038b423aa555a61ffc" in helper
    assert "compressed_block_chunk_count -le 0" in helper
    assert "compressed_block_chunk_count -ne 320" not in helper


def test_runtime_trust_verifier_separates_flat_identity_from_configci_authenticode_hashes():
    body = text(RUNTIME_VERIFY)
    assert RUNTIME_SHA256 in body
    assert PRODUCTION_SETUP_SHA256 in body
    assert "runtime flat SHA256" in body
    assert "Authenticode/PE" in body
    assert "$ExpectedEvidenceRun = 33669452947" in body
    assert "$ExpectedBehavioralRun = 33666343748" in body
    assert "evidence_workflow_run" in body
    assert "behavioral_workflow_run" in body
    assert "historical_anchor_setup_sha256" in body
    for variant in ("Sha1", "Sha256", "Page Sha1", "Page Sha256"):
        assert variant in body
    assert "expected exactly 4 runtime Authenticode/PE hash rules" in body
    assert "SigningScenario 12" in body
    assert "hash_policy_integrated" in body
    assert "ReferenceFullHash" in body
    assert "full-file runtime Sha256 rule does not equal" not in body


def test_enterprise_pack_never_deploys_or_weakens_windows_protection():
    body = text(PACK)
    assert "never deploys App Control policy" in body
    assert "Smart App Control must not be disabled" in body
    assert "Deployment: NOT PERFORMED" in body
    assert "VerifiedAndReputablePolicyState" not in body
    assert "Set-ItemProperty" not in body
    assert "reg.exe add" not in body
    assert "Start-Process -FilePath 'CiTool" not in body
    assert "& $ciTool" not in body


def test_reference_full_hash_requires_exact_sealed_reference_installation():
    body = text(PACK)
    assert "Reference installation does not contain the exact sealed application EXE." in body
    assert "Reference cached repair Setup does not match the exact production installer." in body
    assert "installed-reference-tree" in body


def test_owner_source_mode_is_explicitly_nonproduction_and_never_changes_app_control():
    body = text(OWNER)
    assert "production_distribution = $false" in body
    assert "Smart App Control is not disabled" in body
    assert "App Control policy is not changed" in body
    assert "source mode is owner/developer profile only" in body
    assert "Remove-ItemProperty -LiteralPath $runKey -Name 'ArvectumProxyLauncher'" in body
    assert "main_autostart_enabled = $false" in body
    assert "start/rollback Run ordering races" in body
    assert "EnableAutostart" not in body
    for forbidden in (
        "VerifiedAndReputablePolicyState",
        "CiTool",
        "Set-CIPolicy",
        "ConvertFrom-CIPolicy",
    ):
        assert forbidden not in body


def test_documentation_keeps_russian_provenance_separate_from_windows_execution_trust():
    body = text(DOC)
    lower = body.lower()
    assert "russian" in lower
    assert "smart app control" in lower
    assert "app control for business" in lower
    assert "managed installer" in lower
    assert "hash" in lower
    assert "do **not** disable smart app control" in lower
    assert "release provenance and windows execution trust are separate controls" in lower
