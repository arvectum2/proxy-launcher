"""Conservative WireGuard/AmneziaWG parser boundary until real iOS tunnel QA."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios"


def test_wg_candidate_not_exposed_as_working_transport():
    model = (IOS / "SharedCore/ProxyModel.swift").read_text()
    assert 'case socks5 = "SOCKS5"' in model
    assert "case wireguard" not in model.lower()
    assert "case amnezia" not in model.lower()
    project = (IOS / "project.yml").read_text()
    provider = (IOS / "PacketTunnel/PacketTunnelProvider.swift").read_text()
    assert "WireGuardKit" not in project
    assert "AmneziaWG" not in project
    assert "WireGuardBackend" not in provider
    assert "WGQuickConfigurationPreview" not in provider


def test_wg_preview_cannot_mutate_keys_or_vpn():
    src = (IOS / "SharedCore/WGQuickConfigurationPreview.swift").read_text()
    assert "validKey(properties" in src
    assert "validEndpoint(endpoint)" in src
    assert "Set([h1, h2, h3, h4]).count == 4" in src
    assert "case wireGuard, amneziaWG1" in src
    assert "Peer(endpoint:" in src
    for forbidden in ["SecItem", "UserDefaults", "VPNController",
                      "NEPacketTunnelProvider", "URLSession", "print("]:
        assert forbidden not in src


def test_newer_awg_unsupported_and_source_tests_present():
    tests = (IOS / "Tests/CoreTests/WGQuickConfigurationPreviewTests.swift").read_text()
    assert "testNoAWG2Or3DowngradeToWG1" in tests
    assert "HeaderProtectionKey" in tests
    assert "PostUp" in tests
    assert "testStandardWireGuardPreviewNeverExposesPrivateKeys" in tests
