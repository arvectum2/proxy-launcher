"""Source/privacy gates for alternate IPv6-only upstream reachability QA."""
from pathlib import Path

P = Path(__file__).resolve().parents[1]/'mobile/ios/Tests/DeviceKeychainTests/PhysicalProxyIPFamilyReachabilityTests.swift'


def test_safeguards_and_ipv6_only_endpoints():
    s=P.read_text()
    assert 'testAlternateIPv6OnlyEndpointsAcrossExistingProxiesReadOnly' in s
    assert 'https://v6.ident.me' in s
    assert 'https://ipv6.icanhazip.com' in s
    assert 'NETunnelProviderManager.loadAllFromPreferences' in s
    assert 'manager.connection.status == .disconnected' in s
    assert '#if targetEnvironment(simulator)' in s
    assert 'proxy.allowFailover = false' in s
    assert 'try store.password(for: profile.id)' in s
    assert 'requestFamily(nil, address: endpoint, family: AF_INET6)' in s
    assert 'APL_IPV6_ALTERNATES_UPSTREAM_ENDPOINT1_' in s


def test_never_modifies_vpn_or_logs_private_ip_and_creds():
    s=P.read_text()
    for forbidden in (
        'startVPNTunnel','stopVPNTunnel','saveToPreferences','removeFromPreferences',
        'store.save(', 'SecItemAdd','SecItemDelete',
        'print(pass','print(profile','print(user','print(error','print(ip',
        'String(describing: error)',
    ):
        assert forbidden not in s
