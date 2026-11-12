"""Safety contract for opt-in real physical IPv4/IPv6 PacketTunnel egress."""
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "mobile/ios/Tests/DeviceKeychainTests/PhysicalVPNEgressHostTests.swift"


def test_dualstack_physical_qa_only_with_guards():
    s = P.read_text()
    assert "#if APL_RUN_EXPLICIT_VPN_QA" in s
    assert "#if targetEnvironment(simulator)" in s
    assert "testBoundedAPLPacketTunnelIPv4AndIPv6EgressAndRestore" in s
    assert 'manager.connection.status == .disconnected' in s
    assert '"qaStopAfterSeconds": NSNumber(value: 25)' in s
    assert "deadline: .now() + 20" in s
    assert "session.stopVPNTunnel()" in s
    assert "ipv4.icanhazip.com" in s and "api6.ipify.org" in s
    assert "inet_pton(family" in s
    assert "XCTAssertTrue(changedIPv4" in s and "XCTAssertTrue(changedIPv6" in s
    assert "XCTAssertTrue(restoredIPv4 && restoredIPv6" in s


def test_dualstack_witness_never_logs_addresses_or_changes_user_preferences():
    s = P.read_text()
    for forbidden in (
        "saveToPreferences", "removeFromPreferences", "SecItemAdd",
        "SecItemDelete", "store.save(", "profile.host", "print(before",
        "print(during", "print(after", "print(address", "print(session",
        "print(error", "print(manager",
    ):
        assert forbidden not in s
