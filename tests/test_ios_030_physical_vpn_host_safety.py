"""Explicit opt-in bounded signed PacketTunnel hardware QA source contracts."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "mobile/ios/Tests/DeviceKeychainTests/PhysicalVPNEgressHostTests.swift"


def test_requires_explicit_flag_and_physical_device_and_existing_off_vpn():
    s = SRC.read_text()
    assert "#if APL_RUN_EXPLICIT_VPN_QA" in s
    assert "#if targetEnvironment(simulator)" in s
    assert "throw XCTSkip(" in s
    assert "manager.connection.status == .disconnected" in s
    assert "qaStopAfterSeconds" in s and "NSNumber(value: 25)" in s
    assert "deadline: .now() + 20" in s
    assert "stopItem?.cancel()" in s
    assert "session.stopVPNTunnel()" in s


def test_native_vpn_qa_checks_two_public_witnesses_and_never_logs_private_data():
    s = SRC.read_text()
    assert "NETunnelProviderManager.loadAllFromPreferences" in s
    assert "https://api.ipify.org" in s
    assert "https://www.cloudflare.com/cdn-cgi/trace" in s
    assert "XCTAssertEqual(changed, 2" in s
    assert "XCTAssertEqual(restored, 2" in s
    for forbidden in (
        "saveToPreferences", "removeFromPreferences", "store.save(",
        "SecItemAdd", "SecItemUpdate", "SecItemDelete",
        "print(before", "print(during", "print(after", "print(session",
        "print(profile", "print(error", "profile.host", "password",
        "manager.isEnabled =",
    ):
        assert forbidden not in s
