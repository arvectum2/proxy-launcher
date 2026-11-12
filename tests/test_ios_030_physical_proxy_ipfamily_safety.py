"""Read-only safety and failover contract for per-session IPv4/IPv6 diagnosis."""
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "mobile/ios/Tests/DeviceKeychainTests/PhysicalProxyIPFamilyReachabilityTests.swift"


def test_no_system_vpn_or_profile_mutation_and_no_secret_output():
    t = P.read_text()
    assert "#if targetEnvironment(simulator)" in t and "throw XCTSkip" in t
    assert "NETunnelProviderManager.loadAllFromPreferences" in t
    assert "manager.connection.status == .disconnected" in t
    assert "proxy.allowFailover = false" in t
    assert "proxy.applyCredential(username: username, password: password)" in t
    assert "try store.password(for: profile.id)" in t
    for forbidden in (
        "startVPNTunnel", "stopVPNTunnel", "saveToPreferences",
        "removeFromPreferences", "store.save(", "store.delete(",
        "SecItemAdd", "SecItemDelete", "print(ip", "print(pass",
        "print(user", "print(profile.host", "print(profile.name",
        "String(describing: error)",
    ):
        assert forbidden not in t


def test_diagnosis_checks_both_families_and_reports_anonymous_counts():
    t = P.read_text()
    assert "https://ipv4.icanhazip.com" in t
    assert "https://api6.ipify.org" in t
    assert "inet_pton(family" in t
    assert "APL_PROXY_FAMILY_QA_IPV4_" in t
    assert "APL_PROXY_FAMILY_QA_INDEX_" in t
