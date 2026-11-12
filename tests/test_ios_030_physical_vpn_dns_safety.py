from pathlib import Path

P=Path(__file__).resolve().parents[1]/'mobile/ios/Tests/DeviceKeychainTests/PhysicalVPNEgressHostTests.swift'

def test_diagnostic_preflight_and_guards():
    s=P.read_text()
    assert 'testBoundedAPLPacketTunnelDNSSyntheticAddressDiagnosis' in s
    assert '#if APL_RUN_EXPLICIT_VPN_QA' in s
    assert '#if targetEnvironment(simulator)' in s
    assert 'let session = try await existingOffTunnel()' in s
    assert 'NSNumber(value: 25)' in s
    assert 'deadline: .now() + 20' in s
    assert 'session.stopVPNTunnel()' in s
    assert 'dnsFamilyCounts("ipv4.icanhazip.com")' in s
    assert 'dnsFamilyCounts("httpbingo.org")' in s

def test_no_dns_ip_values_or_mutations_logged():
    s=P.read_text()
    for forbidden in ['print(publicHost','print(ip','print(result','saveToPreferences','removeFromPreferences','SecItemDelete','SecItemAdd','print(session','print(profile.host','print(password','print(manager','print(error']:
        assert forbidden not in s
