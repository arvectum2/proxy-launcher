from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "installer" / "windivert_service_helper.ps1"


def _text():
    return HELPER.read_text(encoding="utf-8-sig")


def test_helper_owns_only_arvectum_service():
    text = _text()
    assert '$ServiceName = "ArvectumProxyWinDivertRouting"' in text
    assert "sc.exe delete $ServiceName" in text
    assert "Stop-Service -Name $ServiceName" in text
    assert "sc.exe delete WinDivert" not in text
    assert "Stop-Service -Name WinDivert" not in text
    assert "Remove-Service WinDivert" not in text


def test_install_verifies_source_before_any_owned_mutation():
    text = _text()
    install = text[text.index("function Install-Stack"):]
    verify = install.index(
        "$verified = Verify-Source -Directory $SourceDirectory"
    )
    remove = install.index("Remove-OwnedService")
    copy = install.index("Copy-Item")
    assert verify < remove < copy


def test_dependency_is_exact_hash_and_signer_pinned():
    text = _text()
    assert (
        "8DA085332782708D8767BCACE5327A6EC7283C17CFB85E40B03CD2323A90DDC2"
        in text
    )
    assert (
        "C1E060EE19444A259B2162F8AF0F3FE8C4428A1C6F694DCE20DE194AC8D7D9A2"
        in text
    )
    assert (
        "043589F75FCE2795E7F2CC3E526D46784D5DDAB3"
        in text
    )
    assert "Get-AuthenticodeSignature" in text
    assert "SignatureStatus]::Valid" in text


def test_service_configuration_is_bfe_auto_and_system_default():
    text = _text()
    assert 'StartupType = "Automatic"' in text
    assert 'DependsOn = "BFE"' in text
    assert "New-Service @serviceArgs" in text
    assert "Credential" not in text
    assert "Start-Service -Name $ServiceName" in text


def test_helper_never_changes_windows_code_integrity_policy():
    lower = _text().lower()
    for forbidden in (
        "testsigning",
        "bcdedit",
        "secureboot",
        "trustedpublisher",
        "cert:\\localmachine\\root",
    ):
        assert forbidden not in lower


def test_marker_matches_runtime_readiness_contract():
    text = _text()
    assert "arvectum.proxy.windows-windivert-stack.v1" in text
    assert "windivert-stack.json" in text
    assert "ArvectumProxyWinDivertRoutingService.exe" in text
    assert "driver_signer_thumbprint" in text
    assert "source_commit" in text


def test_uninstall_removes_only_owned_service_files_and_marker():
    text = _text()
    uninstall = text[
        text.index("function Uninstall-Stack"):
        text.index("function Show-Status")
    ]
    assert "Remove-OwnedService" in uninstall
    assert "Remove-Item -LiteralPath $InstallRoot" in uninstall
    assert "Remove-Item -LiteralPath $MarkerPath" in uninstall
    assert "WinDivert64.sys" not in uninstall
    assert "WinDivert" not in uninstall.replace(
        "ARVECTUM_WINDIVERT_STACK_UNINSTALLED", ""
    )

