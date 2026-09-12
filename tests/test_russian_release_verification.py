from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERIFIER = ROOT / "tools" / "verify_russian_release.ps1"
LAUNCHER = ROOT / "tools" / "VERIFY_RUSSIAN_RELEASE.cmd"
BUNDLER = ROOT / "tools" / "prepare_russian_release_verification_ux.ps1"
DOC = ROOT / "release" / "APL_REL_012_RUSSIAN_RELEASE_VERIFICATION_END_USER_TRUST_UX.md"
WORKFLOW = ROOT / ".github" / "workflows" / "russian-release-verification.yml"


def test_rel012_files_exist():
    for path in (VERIFIER, LAUNCHER, BUNDLER, DOC, WORKFLOW):
        assert path.is_file(), path


def test_verifier_pins_current_governed_arvectum_signer():
    text = VERIFIER.read_text(encoding="utf-8")
    assert "EE1CFA955BA22F03C39C76B183D94CD37494582E" in text
    assert "Get-CmsSignerCertificate" in text
    assert "SignedCms" in text
    assert "SignerInfos.Count -ne 1" in text
    assert "$cmsThumbprint -ne $expectedThumbprint" in text
    assert "$exportedThumbprint -ne $cmsThumbprint" in text
    assert "$evidenceThumbprint -ne $cmsThumbprint" in text
    assert "АРВЕКТУМ" in text


def test_verifier_is_fail_closed_for_manifest_and_release_assets():
    text = VERIFIER.read_text(encoding="utf-8")
    assert "Get-FileHash" in text
    assert "-Algorithm SHA256" in text
    assert "SHA256SUMS.txt" in text
    assert "SHA256SUMS.txt.sig" in text
    assert "signer-certificate.cer" in text
    assert "signing-evidence.json" in text
    assert "IsPathRooted" in text
    assert ".Contains('\\')" in text
    assert ".Contains('/')" in text
    assert "Дублирующееся имя файла" in text
    assert "неподписанный/неучтённый файл" in text
    assert "Нарушена целостность файла" in text


def test_verifier_requires_positive_cryptopro_detached_verification():
    text = VERIFIER.read_text(encoding="utf-8")
    assert "Crypto Pro\\CSP\\csptest.exe" in text
    assert "'-sfsign', '-verify', '-detached'" in text
    assert "verified\\s+OK" in text
    assert "ErrorCode:\\s*0x00000000" in text
    assert "CryptoPro не подтвердил detached-подпись" in text


def test_verifier_cross_checks_non_secret_evidence_without_treating_it_as_trust_anchor():
    text = VERIFIER.read_text(encoding="utf-8")
    assert "russian-qualified-evidence" in text
    assert "embedded_code_signing_activated" in text
    assert "detached_signature_verified" in text
    assert "manifest_sha256" in text
    assert "manifest_signature_sha256" in text
    assert "evidence.assets" in text
    # The actual signer identity is taken from the signed CMS, not trusted from JSON alone.
    assert "$cmsSigner = Get-CmsSignerCertificate" in text


def test_end_user_ux_is_russian_and_never_overclaims_windows_trust():
    verifier = VERIFIER.read_text(encoding="utf-8")
    launcher = LAUNCHER.read_text(encoding="utf-8")
    combined = verifier + launcher
    assert "РЕЗУЛЬТАТ: ПРОВЕРКА ПРОЙДЕНА" in verifier
    assert "РЕЗУЛЬТАТ: ПРОВЕРКА НЕ ПРОЙДЕНА" in verifier
    assert "APL_REL_012_RESULT=PASS" in verifier
    assert "APL_REL_012_RESULT=FAIL" in verifier
    assert "Не запускайте файлы" in combined
    assert "НЕ означает, что EXE имеет Microsoft Authenticode-подпись" in verifier
    assert "НЕ означает репутацию SmartScreen" in verifier
    assert "RELEASE-EVIDENCE-ONLY" in verifier


def test_one_click_launcher_runs_only_the_bundled_verifier_and_decodes_utf8_explicitly():
    text = LAUNCHER.read_text(encoding="utf-8")
    lowered = text.lower()
    assert "%~dp0verify_russian_release.ps1" in lowered
    assert "apl_verify_script" in lowered
    assert "apl_verify_dir" in lowered
    assert "-noprofile" in lowered
    assert "-executionpolicy bypass" in lowered
    assert "readalltext" in lowered
    assert "text.encoding]::utf8" in lowered
    assert "[scriptblock]::create" in lowered
    assert "-releasedirectory $env:apl_verify_dir" in lowered
    assert "pause" in lowered


def test_bundler_places_powershell51_safe_verifier_before_rel011_signing():
    text = BUNDLER.read_text(encoding="utf-8")
    assert "verify_russian_release.ps1" in text
    assert "VERIFY_RUSSIAN_RELEASE.cmd" in text
    assert "ReadAllText" in text
    assert "System.Text.Encoding]::UTF8" in text
    assert "UTF8Encoding" in text
    assert "WriteAllText" in text
    assert "0xEF" in text and "0xBB" in text and "0xBF" in text
    assert "BEFORE tools/russian_signed_release.ps1" in text
    assert "included in SHA256SUMS.txt" in text


def test_doc_defines_three_distinct_trust_layers_and_fail_closed_publication():
    text = DOC.read_text(encoding="utf-8")
    assert "Криптографическая целостность" in text
    assert "Подлинность релиза" in text
    assert "OS-native publisher trust" in text
    assert "SmartScreen" in text
    assert "VERIFY_RUSSIAN_RELEASE.cmd" in text
    assert "CryptoPro CSP" in text
    assert "НЕ ПУБЛИКОВАТЬ" in text


def test_workflow_is_non_secret_and_checks_powershell_syntax():
    text = WORKFLOW.read_text(encoding="utf-8")
    lowered = text.lower()
    assert "permissions:" in text
    assert "contents: read" in text
    assert "pytest" in lowered
    assert "windows-latest" in lowered
    assert "parser]::parseinput" in lowered
    assert "readalltext" in lowered
    assert "text.encoding]::utf8" in lowered
    assert "${{ secrets." not in lowered
    assert "-sfsign" not in lowered
