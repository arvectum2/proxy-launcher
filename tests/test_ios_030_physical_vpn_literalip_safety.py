"""Safety gate for opt-in physical public numeric IPv4/IPv6 route probe."""
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "mobile/ios/Tests/DeviceKeychainTests/PhysicalVPNEgressHostTests.swift"


def test_literal_public_ip_probe_has_preflight_and_two_guards():
    t = P.read_text()
    assert "testBoundedAPLPacketTunnelLiteralIPv4IPv6RoutesAndRestore" in t
    assert "#if APL_RUN_EXPLICIT_VPN_QA" in t
    assert "#if targetEnvironment(simulator)" in t
    assert "let session = try await existingOffTunnel()" in t
    assert "https://1.1.1.1/cdn-cgi/trace" in t
    assert "https://[2606:4700:4700::1111]/cdn-cgi/trace" in t
    assert "qaStopAfterSeconds" in t and "NSNumber(value: 25)" in t
    assert "deadline: .now() + 20" in t
    assert "session.stopVPNTunnel()" in t
    assert "XCTAssertTrue(restoredV4 && restoredV6" in t


def test_literal_probe_never_disables_tls_or_logs_origin_or_creds():
    t = P.read_text()
    for forbidden in (
        "allowInvalidCertificates", "setAllowsAnyHTTPSCertificate",
        "SecTrustSetExceptions", "saveToPreferences", "removeFromPreferences",
        "print(origin", "print(before", "print(after", "print(profile",
        "print(password", "print(manager", "print(error", "SecItemDelete",
        "SecItemAdd", "store.save(",
    ):
        assert forbidden not in t
