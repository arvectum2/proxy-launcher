"""Fail-closed source gate for the *unshipped* VLESS/REALITY candidate."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios"


def test_source_candidate_does_not_enable_a_protocol_before_native_gate():
    model = (IOS / "SharedCore/ProxyModel.swift").read_text()
    assert 'case socks5 = "SOCKS5"' in model
    assert "case vless" not in model.lower()
    assert "case wireguard" not in model.lower()
    assert "case amnezia" not in model.lower()
    assert "LibXray.xcframework" not in (IOS / "project.yml").read_text()
    assert "LibXray" not in (IOS / "PacketTunnel/PacketTunnelProvider.swift").read_text()


def test_vless_parser_is_pure_and_uses_pinned_cgo_api_v3():
    text = (IOS / "SharedCore/VLESSRealityShareLink.swift").read_text()
    assert "struct VLESSRealityShareLink" in text
    assert "conversionRequest()" in text
    assert 'method: "convertShareLinksToXrayJson"' in text
    assert "apiVersion: 3" in text
    assert "ManagedProfileContract.validDNS(sni)" in text
    assert "publicKeyBytes(keyString)" in text
    assert "allowedKeys" in text
    assert "URLSession" not in text
    assert "SecItem" not in text
    assert "VPNController" not in text


def test_existing_importer_rejects_inactive_vless_links():
    tests = (IOS / "Tests/CoreTests/ProxyImportTests.swift").read_text()
    assert "vless://a@b:443" in tests
    tests_new = (IOS / "Tests/CoreTests/VLESSRealityShareLinkTests.swift").read_text()
    assert "testExistingProxyImporterNeverMislabeledVLESSAsHTTP" in tests_new
