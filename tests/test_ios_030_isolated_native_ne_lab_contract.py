"""Source-only isolation guards; never substitutes for actual signed NE QA."""
from pathlib import Path

IOS = Path(__file__).resolve().parents[1] / "mobile/ios"
LAB = IOS / "Tools/NativeTunnelLab"


def test_isolated_lab_not_in_production_targets():
    for path in (IOS / "project.yml", IOS / "ArvectumProxyLauncherIOS.xcodeproj/project.pbxproj"):
        text = path.read_text()
        assert "NativeLabPacketTunnelProvider" not in text
        assert "NativeTunnelLab" not in text
        assert "LibXray" not in text


def test_only_explicit_synthetic_route_and_no_owner_storage():
    src = (LAB / "NativeLabPacketTunnelProvider.swift").read_text()
    assert '== "explicit-lab-v1"' in src
    assert 'candidate.serverPort == 39882' in src
    assert 'NEIPv4Route(destinationAddress:"198.51.100.77",subnetMask:"255.255.255.255")' in src
    for forbidden in ("NEIPv4Route.default()", "dnsSettings", "ipv6Settings", "UserDefaults", "SecItem", "ProfileStore"):
        assert forbidden not in src
    assert "TunnelEngineHandoff.stopAndDrain" in src
    assert "gate.markUnexpectedExit" in src
    assert "retired = true" in src


def test_exact_descriptor_selection_never_falls_back():
    src = (LAB / "ExactLabTUNDescriptor.swift").read_text()
    assert 'names.count == 1' in src
    assert 'matches.count == 1 ? matches[0] : nil' in src


def test_unsigned_build_does_not_install_or_create_provisioning_profile():
    src = (LAB / "build_unsigned.sh").read_text()
    assert "CODE_SIGNING_ALLOWED: NO" in src
    assert "ru.arvectum.proxylauncher.lab.nativeqa.PacketTunnel" in src
    assert "verify_xray_apple_provenance.py" in src
    assert "_CGoInvoke" in src and "_tun2proxy_run_with_cli_args" in src
    for forbidden in ("-allowProvisioningUpdates", "devicectl device install", "simctl install"):
        assert forbidden not in src
