"""Static review guards for the isolated physical UDP QA witness."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / "mobile/ios/Tools/NativeUDPPhysicalProbe"
SWIFT = (QA / "Host/QAUDPHost.swift").read_text()
PROJECT = (QA / "project.yml").read_text()

def test_not_shipped_in_product_or_vpn_manager():
    project = (ROOT / "mobile/ios/ArvectumProxyLauncherIOS.xcodeproj/project.pbxproj").read_text()
    assert "NativeUDPPhysicalProbe" not in project
    assert "import NetworkExtension" not in SWIFT
    for token in ("NETunnelProviderManager", "startVPNTunnel", "startTunnel(", "removeFromPreferences"):
        assert token not in SWIFT
    assert "CODE_SIGNING_ALLOWED: NO" in PROJECT
    assert "type: app-extension" not in PROJECT

def test_fixed_nonce_and_synthetic_endpoint_only():
    for token in ("198.51.100.77", "2001:db8:77::77", "39883", "APL_UDP:", "APL_RECEIPT:"):
        assert token in SWIFT
    assert "using:.udp" in SWIFT
    assert "tcp4Control" in SWIFT and "udp4Reply" in SWIFT and "udp6Reply" in SWIFT
    assert "response ==" in SWIFT
    assert "urlCache=nil" in SWIFT

def test_opt_in_private_one_shot_input():
    assert 'contains("--apl-product-udp-only")' in SWIFT
    assert "guard !used" in SWIFT
    assert "value.nonce.utf8.count==40" in SWIFT
    assert "(48...57).contains($0) || (97...102).contains($0)" in SWIFT
    assert "FileManager.default.removeItem(at:input)" in SWIFT
    assert "FileManager.default.urls(for:.documentDirectory" in SWIFT

def test_explicit_unsigned_standalone_target():
    assert "ru.arvectum.proxylauncher.lab.httpswitness" in PROJECT
    assert "NativeLabHost:" in PROJECT
    assert 'iOS: "15.0"' in PROJECT
    assert "NSAllowsArbitraryLoads: true" in PROJECT
    assert "CODE_SIGNING_ALLOWED: NO" in PROJECT
