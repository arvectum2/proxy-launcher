from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / "tools" / "russian_production_release_gate.ps1"
DOC = ROOT / "release" / "APL_REL_013_RUSSIAN_PRODUCTION_RELEASE_GATE.md"
WORKFLOW = ROOT / ".github" / "workflows" / "russian-production-release-gate.yml"


def test_rel013_files_exist():
    for path in (GATE, DOC, WORKFLOW):
        assert path.is_file(), path


def test_gate_is_bound_to_rel011_and_rel012_evidence_chain():
    text = GATE.read_text(encoding="utf-8")
    assert "signing-evidence.json" in text
    assert "SHA256SUMS.txt" in text
    assert "SHA256SUMS.txt.sig" in text
    assert "signer-certificate.cer" in text
    assert "verify_russian_release.ps1" in text
    assert "VERIFY_RUSSIAN_RELEASE.cmd" in text
    assert "APL-REL-011" in text
    assert "russian-qualified-evidence" in text
    assert "detached_signature_verified" in text
    assert "Invoke-ReleaseVerifier" in text
    assert "APL_REL_012_RESULT=PASS" in text
    assert "APL_REL_012_RESULT=FAIL" in text


def test_gate_source_is_ascii_safe_for_windows_powershell_51_file_execution():
    # Windows PowerShell 5.1 may decode BOM-less UTF-8 scripts as ANSI. Keep the
    # REL-013 source ASCII-only so direct `powershell.exe -File` remains safe.
    GATE.read_bytes().decode("ascii")
    text = GATE.read_text(encoding="ascii")
    assert "0x0410" in text
    assert "[regex]::Escape($arvectumName)" in text


def test_gate_requires_signed_rel014_exact_lifecycle_evidence():
    text = GATE.read_text(encoding="utf-8")
    assert "apl-rel-014-lifecycle-evidence.json" in text
    assert "arvectum.proxy.apl-rel-014-exact-evidence.v1" in text
    assert "EXACT_PRODUCT_SET_READY_FOR_REL011_SIGNING" in text
    assert "APL_REL_014_EXACT_SIGNED_SET_CONTRACT.json" in text
    assert "contract_sha256" in text
    assert "candidate_source_commit" in text
    assert "release_assets.setup.sha256" in text
    assert "release_assets.portable_zip.sha256" in text
    assert "release_assets.application_inside_lifecycle.sha256" in text
    assert "Assert-SignedRel014Asset" in text
    assert "rel014_exact_lifecycle_evidence = 'PASS'" in text
    assert "rel014_signed_asset_binding = 'PASS'" in text
    assert "rel014_evidence_sha256" in text


def test_gate_pins_governed_arvectum_signer_and_sensitive_key_boundaries():
    text = GATE.read_text(encoding="utf-8")
    assert "EE1CFA955BA22F03C39C76B183D94CD37494582E" in text
    assert "$arvectumName" in text
    assert "pin_stored" in text
    assert "private_key_export_attempted" in text
    assert "Publication is forbidden" in text
    lowered = text.lower()
    assert "-sfsign" not in lowered
    assert "certificate_has_private_key" not in lowered


def test_gate_requires_exact_version_tag_commit_and_canonical_main_provenance():
    text = GATE.read_text(encoding="utf-8")
    assert "Version/tag mismatch" in text
    assert "evidence.git_tag" in text
    assert "evidence.git_commit" in text
    assert "@('rev-parse', 'HEAD')" in text
    assert 'Invoke-Git @(\'rev-parse\', "$GitTag^{commit}")' in text
    assert "merge-base --is-ancestor" in text
    assert "@('status', '--porcelain')" in text
    assert "Current HEAD is not the exact release commit" in text
    assert "Git worktree is not clean" in text


def test_gate_requires_negative_tamper_test_to_fail_closed():
    text = GATE.read_text(encoding="utf-8")
    assert "APL-REL-013-TAMPER-TEST" in text
    assert "ExpectSuccess $false" in text
    assert "Negative tamper test unexpectedly passed" in text
    assert "Remove-Item -LiteralPath $tempRoot -Recurse -Force" in text
    assert "tampered copy correctly rejected" in text


def test_gate_decision_is_outside_release_and_explicit_about_trust_boundary():
    text = GATE.read_text(encoding="utf-8")
    assert ".production-release-gate.json" in text
    assert "Decision output must be outside the signed release directory" in text
    assert "decision = 'PUBLISH'" in text
    assert "embedded_code_signing_activated = $false" in text
    assert "authenticode_trust_claimed = $false" in text
    assert "smartscreen_trust_claimed = $false" in text
    assert "Publication decision: PUBLISH" in text


def test_doc_defines_fail_closed_publication_gate_and_per_release_ceremony():
    text = DOC.read_text(encoding="utf-8")
    assert "НЕ ПУБЛИКОВАТЬ" in text
    assert "PUBLISH" in text
    assert "REL-011" in text
    assert "REL-012" in text
    assert "negative tamper" in text.lower()
    assert "production-release-gate.json" in text
    assert "каждого релиза" in text
    assert "Authenticode" in text
    assert "SmartScreen" in text


def test_workflow_is_non_secret_and_only_validates_repository_contract():
    text = WORKFLOW.read_text(encoding="utf-8")
    lowered = text.lower()
    assert "permissions:" in text
    assert "contents: read" in text
    assert "pytest" in lowered
    assert "windows-latest" in lowered
    assert "parser]::parseinput" in lowered
    assert "${{ secrets." not in lowered
    assert "-sfsign" not in lowered
    assert "rutoken" not in lowered
