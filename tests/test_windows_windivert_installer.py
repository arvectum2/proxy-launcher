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



def test_canonical_installer_accepts_only_commit_bound_windivert_bundle():
    builder = (
        ROOT / "tools" / "build_windows_installer.ps1"
    ).read_text(encoding="utf-8-sig")
    assert "[string]$WinDivertStackBundle" in builder
    assert "WinDivertStackBundle and NativeStackBundle are mutually exclusive" in builder
    assert "arvectum.proxy.windows-windivert-build.v1" in builder
    assert "source_commit does not match HEAD" in builder
    assert "WinDivertStackBundle service hash mismatch" in builder
    assert "WinDivertStackBundle driver signature identity mismatch" in builder
    assert "WinDivertSourceCommit" in builder


def test_inno_embeds_windivert_stack_and_uses_standard_uac():
    script = (
        ROOT / "installer" / "ArvectumProxyLauncher.iss"
    ).read_text(encoding="utf-8-sig")
    assert "PrivilegesRequired=lowest" in script
    assert "WinDivertStackPayloadDir" in script
    assert "ArvectumProxyWinDivertRoutingService.exe" in script
    assert "windivert-dependency.json" in script
    assert "windivert-stack-build.json" in script
    assert "windivert_service_helper.ps1" in script
    assert "ShellExec('runas', PowerShell" in script
    assert "-Action Install -SourceDirectory" in script
    assert "-Action Uninstall" in script


def test_installer_never_embeds_test_mode_for_production_windivert():
    builder = (
        ROOT / "tools" / "build_windows_installer.ps1"
    ).read_text(encoding="utf-8-sig")
    assert "WindowsAppExclusionsPreview cannot use the production WinDivert stack" in builder
    script = (
        ROOT / "installer" / "ArvectumProxyLauncher.iss"
    ).read_text(encoding="utf-8-sig")
    section = script[
        script.index("#ifdef WinDivertStackPayloadDir"):
        script.index("#define AppName")
    ]
    assert "windows_preview_mode_helper" not in section.lower()


def test_third_party_notice_covers_redistributed_windivert():
    notice = (ROOT / "THIRD_PARTY_NOTICES.txt").read_text(
        encoding="utf-8-sig"
    )
    assert "WinDivert 2.2.2" in notice
    assert "LGPL-3.0-or-later OR GPL-2.0" in notice
    assert "WinDivert-LICENSE" in notice
