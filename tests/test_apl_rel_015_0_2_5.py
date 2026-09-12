import hashlib
import importlib.util
import json
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "release" / "APL_REL_015_0_2_5_CFA_HOTFIX_CONTRACT.json"
RAW_PHYSICAL = ROOT / "docs" / "evidence" / "APL_0_2_5_FINAL_PHYSICAL_REBOOT_2026-09-13.json"
MATERIALIZER = ROOT / "tools" / "materialize_0_2_5_accepted_portable.ps1"
BINDER = ROOT / "tools" / "apl_rel_015_0_2_5_exact_evidence.py"
GATE = ROOT / "tools" / "russian_production_release_gate_0_2_5.ps1"
DOC = ROOT / "release" / "APL_REL_015_0_2_5_CFA_HOTFIX_RELEASE_EVIDENCE.md"
WORKFLOW = ROOT / ".github" / "workflows" / "russian-production-release-gate.yml"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _load_binder():
    spec = importlib.util.spec_from_file_location("apl_rel_015_test_module", BINDER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_rel015_contract_pins_the_physically_accepted_0_2_5_identity():
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert contract["schema"] == "arvectum.proxy.apl-rel-015-cfa-hotfix-contract.v1"
    assert contract["task"] == "APL-REL-015"
    assert contract["version"] == "0.2.5"
    assert contract["accepted_product_source_commit"] == "9e8ca7e851563082cd7d03d7543ccb360a37ec27"
    candidate = contract["accepted_installer_candidate"]
    assert candidate["github_run_id"] == "34720855917"
    assert candidate["artifact_id"] == "10306540886"
    assert candidate["artifact_zip_sha256"] == "a9c973b68bfd58ff7c16afedb0d13edf98173ab0d690e189580e6f45327362ec"
    assert candidate["setup_sha256"] == "9b5368d67874b7164ee56a245c75db4b23af593a1d72f7e947774516abcc95e3"
    assert candidate["application_sha256"] == "1ab36b7a6a0a225dcf06fb2c630d0d2ba47ec17578dbd5949f08e992853d653c"
    assert candidate["recorded_same_run_portable_sha256"] == "7e65d980b376977b33263a7b7ad97ade9c3c83f3eb685c5ab624ce342fb71af0"
    assert contract["physical_acceptance"]["sha256"] == "2afe6af76a69dc4d0b6869385dda6c4467c3d01e38997a04ca554c28aa24021a"
    assert contract["physical_acceptance"]["schema"] == "arvectum.proxy.0.2.5.final-physical-reboot.v1"
    assert "https_through_proxy" in contract["physical_acceptance"]["required_checks"]
    assert contract["russian_release"]["required_signer_thumbprint"] == "EE1CFA955BA22F03C39C76B183D94CD37494582E"


def test_raw_physical_evidence_is_preserved_exactly_and_all_final_checks_pass():
    assert _sha256(RAW_PHYSICAL) == "2afe6af76a69dc4d0b6869385dda6c4467c3d01e38997a04ca554c28aa24021a"
    physical = json.loads(RAW_PHYSICAL.read_text(encoding="utf-8-sig"))
    assert physical["schema"] == "arvectum.proxy.0.2.5.final-physical-reboot.v1"
    assert physical["source_commit"] == "9e8ca7e851563082cd7d03d7543ccb360a37ec27"
    assert physical["result"] == "PASS"
    assert physical["application"]["version"] == "0.2.5"
    assert physical["application"]["sha256"] == "1ab36b7a6a0a225dcf06fb2c630d0d2ba47ec17578dbd5949f08e992853d653c"
    assert physical["network"]["pac_http_status"] == 200
    assert physical["network"]["https_status"] == 200
    assert all(value is True for value in physical["checks"].values())


def test_materializer_is_packaging_only_and_requires_exact_accepted_application():
    text = MATERIALIZER.read_text(encoding="utf-8")
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert "materialization must run on Windows" in text
    assert "required_application_sha256" in text
    assert "template_source.inner_portable_zip_sha256" in text
    assert "required_static_members" in text
    assert "Copy-Item -LiteralPath $acceptedApp -Destination $templateApp -Force" in text
    assert "Compress-Archive" in text
    assert "Expand-Archive" in text
    assert "Output already exists; refusing to overwrite" in text
    lowered = text.lower()
    assert "pyinstaller" not in lowered
    assert "clean_build_windows" not in lowered
    assert "pip install" not in lowered
    assert contract["portable_materialization"]["policy"] == "repackage-exact-physically-accepted-application"


def test_binder_validates_a_materialized_portable_with_exact_accepted_application(tmp_path):
    module = _load_binder()
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    expected_app = contract["portable_materialization"]["required_application_sha256"]
    # For this focused unit test, make synthetic application bytes and adapt a
    # copy of the contract to their real SHA-256. Static members stay contract-bound.
    app_bytes = b"exact-accepted-app-fixture"
    synthetic_app_hash = hashlib.sha256(app_bytes).hexdigest()
    synthetic = json.loads(json.dumps(contract))
    synthetic["portable_materialization"]["required_application_sha256"] = synthetic_app_hash
    for name in list(synthetic["portable_materialization"]["required_static_members"]):
        data = ("static:" + name).encode("utf-8")
        synthetic["portable_materialization"]["required_static_members"][name] = hashlib.sha256(data).hexdigest()

    portable = tmp_path / "Arvectum-Proxy-Launcher-0.2.5-windows-x64-portable.zip"
    with zipfile.ZipFile(portable, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("Arvectum Proxy Launcher.exe", app_bytes)
        archive.writestr("SHA256SUMS.txt", f"{synthetic_app_hash}  Arvectum Proxy Launcher.exe\r\n")
        for name in synthetic["portable_materialization"]["required_static_members"]:
            archive.writestr(name, ("static:" + name).encode("utf-8"))

    result = module.validate_portable(synthetic, portable)
    assert result["application_sha256"] == synthetic_app_hash
    assert result["sha256"] == hashlib.sha256(portable.read_bytes()).hexdigest()
    assert result["member_count"] == 2 + len(synthetic["portable_materialization"]["required_static_members"])
    assert result["materialization_policy"] == "repackage-exact-physically-accepted-application"
    assert expected_app == "1ab36b7a6a0a225dcf06fb2c630d0d2ba47ec17578dbd5949f08e992853d653c"


def test_binder_rejects_portable_with_wrong_application(tmp_path):
    module = _load_binder()
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    portable = tmp_path / "Arvectum-Proxy-Launcher-0.2.5-windows-x64-portable.zip"
    with zipfile.ZipFile(portable, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("Arvectum Proxy Launcher.exe", b"wrong-app")
        archive.writestr("SHA256SUMS.txt", "wrong")
        for name in contract["portable_materialization"]["required_static_members"]:
            archive.writestr(name, b"wrong-static")
    try:
        module.validate_portable(contract, portable)
    except module.EvidenceError as exc:
        assert "physically accepted application" in str(exc)
    else:
        raise AssertionError("wrong portable application was accepted")


def test_binder_requires_ci_cfa_physical_and_toolchain_boundaries():
    text = BINDER.read_text(encoding="utf-8")
    for token in (
        "windows-installer-171-e2e.v2",
        "active_runtime_continuity",
        "cfa_safe_localappdata_target",
        "windows-rc-e2e.v2",
        "fresh_install_smoke",
        "foreign_startup_preserved",
        'physical.get("schema") == pc["schema"]',
        'pc["required_checks"]',
        'network.get("https_status")',
        "BUILD_PYTHON_VERSION",
        "requirements-build.lock.txt",
        "READY_FOR_REL011_SIGNING",
        "APL_REL_015_RESULT=PASS",
    ):
        assert token in text


def test_0_2_5_gate_preserves_rel011_rel012_and_adds_rel015_binding():
    text = GATE.read_text(encoding="ascii")
    for token in (
        "APL-REL-011",
        "russian-qualified-evidence",
        "detached_signature_verified",
        "APL_REL_012_RESULT=PASS",
        "APL_REL_012_RESULT=FAIL",
        "apl-rel-015-cfa-hotfix-evidence.json",
        "arvectum.proxy.apl-rel-015-cfa-hotfix-evidence.v1",
        "APL_REL_015_0_2_5_CFA_HOTFIX_CONTRACT.json",
        "rel015_exact_hotfix_evidence = 'PASS'",
        "rel015_signed_asset_binding = 'PASS'",
        "APL-REL-013-015-TAMPER-TEST",
        "Publication decision: PUBLISH",
    ):
        assert token in text
    assert "EE1CFA955BA22F03C39C76B183D94CD37494582E" in text
    assert "embedded_code_signing_activated = $false" in text
    assert "authenticode_trust_claimed = $false" in text
    assert "smartscreen_trust_claimed = $false" in text
    assert "-sfsign" not in text.lower()


def test_0_2_5_gate_requires_exact_git_provenance_and_clean_worktree():
    text = GATE.read_text(encoding="ascii")
    assert "Version/tag mismatch" in text
    assert "@('rev-parse', 'HEAD')" in text
    assert 'Invoke-Git @(\'rev-parse\', "$GitTag^{commit}")' in text
    assert "merge-base --is-ancestor" in text
    assert "@('status', '--porcelain')" in text
    assert "Current HEAD is not the exact release commit" in text
    assert "Git worktree is not clean" in text


def test_rel015_release_document_and_workflow_cover_new_profile():
    assert DOC.is_file()
    text = DOC.read_text(encoding="utf-8")
    assert "0.2.5" in text
    assert "APL-REL-015" in text
    assert "1ab36b7a6a0a225dcf06fb2c630d0d2ba47ec17578dbd5949f08e992853d653c" in text
    assert "9b5368d67874b7164ee56a245c75db4b23af593a1d72f7e947774516abcc95e3" in text
    assert "REL-011" in text and "REL-012" in text and "REL-013" in text
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "test_apl_rel_015_0_2_5.py" in workflow
    assert "russian_production_release_gate_0_2_5.ps1" in workflow
    assert "materialize_0_2_5_accepted_portable.ps1" in workflow
