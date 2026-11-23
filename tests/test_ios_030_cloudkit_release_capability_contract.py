"""CloudKit opt-in release staging must never silently mutate the live app profile."""
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios"


def test_cloudkit_entitlement_is_host_only_additive_and_private():
    old = plistlib.loads((IOS / "Config/App.entitlements").read_bytes())
    full = plistlib.loads((IOS / "Config/App-CloudKit.entitlements").read_bytes())
    assert not any("icloud" in k.lower() for k in old)
    assert set(full) == set(old) | {
        "com.apple.developer.icloud-services",
        "com.apple.developer.icloud-container-identifiers",
    }
    for key in old:
        assert full[key] == old[key]
    assert full["com.apple.developer.icloud-services"] == ["CloudKit"]
    assert full["com.apple.developer.icloud-container-identifiers"] == [
        "iCloud.ru.arvectum.proxylauncher.ios"
    ]
    provider = plistlib.loads((IOS / "Config/PacketTunnel.entitlements").read_bytes())
    assert not any("icloud" in k.lower() for k in provider)


def test_cloudkit_release_is_explicit_opt_in_only_and_source_matches():
    stage = (IOS / "Tools/stage_ios_030_release_candidate.py").read_text()
    spec = (IOS / "project.yml").read_text()
    view = (IOS / "App/ExclusionsView.swift").read_text()
    service = (IOS / "App/ExclusionCloudKitService.swift").read_text()
    assert "parser.add_argument('--cloudkit', action='store_true'" in stage
    assert "a.cloudkit" in stage
    assert "CODE_SIGN_ENTITLEMENTS: Config/App-CloudKit.entitlements" in stage
    assert "'cloudkit_provisioned':False" in stage
    assert "APL_CLOUDKIT_ENABLED" in view
    assert 'iCloud.ru.arvectum.proxylauncher.ios' in service
    # Active default/signed candidate still uses original, authorized profile.
    assert "Config/App-CloudKit.entitlements" not in spec
    assert "APL_CLOUDKIT_ENABLED" not in spec


def test_vless_qa_flag_cannot_enter_signed_release_staging():
    stage = (IOS / "Tools/stage_ios_030_release_candidate.py").read_text()
    assert "'APL_VLESS_PHYSICAL_QA'" in stage
    src = (IOS / "SharedCore/NativeCredentialRecord.swift").read_text()
    assert "#if APL_NATIVE_PRODUCT_RUNTIME && !APL_VLESS_PHYSICAL_QA" in src
    assert "return false" in src
    runner = (IOS / "PacketTunnel/NativeXrayPacketSession.swift").read_text()
    assert "physicalUnderlayInterface()" in runner
    assert "bindPhysicalUnderlay(" in runner
    assert "monitor.pathUpdateHandler" in runner
