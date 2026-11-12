"""Source safety contracts for signed physical-only Apple proxy HTTPS witness."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mobile/ios/Tests/DeviceKeychainTests/PhysicalHTTPSReceiptReadOnlyTests.swift"


def test_https_witness_is_fail_closed_and_proves_nonce_and_origin():
    s = SOURCE.read_text()
    assert "config.proxyConfigurations = [proxy]" in s
    assert "proxy.allowFailover = false" in s
    assert "proxy.applyCredential(username: user, password: password)" in s
    assert "echoed == nonce" in s
    assert "origin != directOrigin" in s
    assert "testExistingProfilesProduceExternalHTTPSNonceWithoutSystemVPN" in s
    assert "https://httpbingo.org/get?qa_nonce=" in s


def test_https_witness_skips_ci_and_cannot_change_vpn_or_log_secrets():
    s = SOURCE.read_text()
    assert "#if targetEnvironment(simulator)" in s and "throw XCTSkip" in s
    assert "store.password(for: profile.id)" in s
    for forbidden in (
        "store.save(", "store.delete(", "SecItemDelete", "SecItemAdd",
        "NEPacketTunnelProvider", "NETunnelProviderManager",
        "connectVPN(", "startTunnel(", "setPassword(",
        "print(origin", "print(directOrigin", "print(password", "print(user",
        "print(profile.host", "print(profile.name", "XCTAssertNotEqual(origin",
        "String(describing: error)",
    ):
        assert forbidden not in s
