"""Protect opt-in IPv4/IPv6 readiness tests from VPN, profile mutation and IP leakage."""
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "mobile/ios/Tests/DeviceKeychainTests/PhysicalIPFamilyReadOnlyTests.swift"


def test_ip_family_qa_precondition_off_and_simulator_skip():
    s = P.read_text()
    assert "NETunnelProviderManager.loadAllFromPreferences" in s
    assert "manager.connection.status == .disconnected" in s
    assert "#if targetEnvironment(simulator)" in s
    assert "throw XCTSkip" in s
    assert "https://api4.ipify.org" in s
    assert "https://api6.ipify.org" in s
    assert "inet_pton(family" in s
    assert "AF_INET" in s and "AF_INET6" in s


def test_ip_family_qa_never_changes_vpn_or_logs_private_address():
    s = P.read_text()
    for forbidden in (
        "session.startTunnel", "session.stopVPNTunnel", "startVPNTunnel",
        "saveToPreferences", "removeFromPreferences", "store.save(",
        "SecItemCopyMatching", "SecItemAdd", "SecItemDelete",
        "print(address", "print(text", "print(manager", "print(profile",
        "String(describing: error)",
    ):
        assert forbidden not in s
