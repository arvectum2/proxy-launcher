"""Guards read-only preflight for optional, explicitly bounded iPhone system VPN QA."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "mobile/ios/Tests/DeviceKeychainTests/PhysicalVPNStatusReadOnlyTests.swift"


def test_preflight_uses_only_existing_manager_and_requires_off():
    s = SRC.read_text()
    assert "NETunnelProviderManager.loadAllFromPreferences" in s
    assert "status == .disconnected || status == .invalid" in s
    assert 'APL_VPN_QA_READONLY_OFF_CONFIRMED' in s
    assert "#if targetEnvironment(simulator)" in s
    for forbidden in (
        "saveToPreferences", "removeFromPreferences", "startVPNTunnel",
        "stopVPNTunnel", "startTunnel(", "NETunnelProviderManager()",
        "store.save(", "SecItemAdd", "SecItemDelete", "print(status",
        "profile.host", "print(manager",
    ):
        assert forbidden not in s
