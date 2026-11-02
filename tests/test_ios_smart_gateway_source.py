"""Mobile opt-in gateway contract: exact host is remote, not local /32."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
IOS=ROOT/'mobile/ios'
PROFILE=(IOS/'SharedCore/ProxyModel.swift').read_text()
TUNNEL=(IOS/'PacketTunnel/PacketTunnelProvider.swift').read_text()
SYNC=(IOS/'PacketTunnel/SmartGatewayPolicySync.swift').read_text()
POLICY=(IOS/'SharedCore/SmartGatewayExclusionPolicy.swift').read_text()
PROBE=(IOS/'Shared/ProxyProbe.swift').read_text()


def test_gateway_is_explicit_tls_authenticated_opt_in():
    assert 'case gateway = "APL_GATEWAY"' in PROFILE
    assert 'case .https, .gateway: try await probeHTTP(profile, password: password, tls: true)' in PROBE
    assert 'effective.type == .https || effective.type == .gateway' in TUNNEL
    assert 'case .https, .gateway, .auto: throw tunnelError' in TUNNEL


def test_gateway_mode_never_creates_site_wide_ip_routes():
    assert 'if prepared.resolvedProfile.type == .gateway' in TUNNEL
    assert 'try await SmartGatewayPolicySync.push' in TUNNEL
    assert 'addresses: try resolveHost(prepared.storedProfile.host),' in TUNNEL
    assert 'dnsBypass: []' in TUNNEL
    assert 'let dnsBypassFlags = exclusions.dnsBypass.map' in TUNNEL
    assert 'try await SmartGatewayPolicySync.push' in TUNNEL
    assert 'startGatewayPolicyRefresh(prepared)' in TUNNEL
    assert '60_000_000_000' in TUNNEL


def test_exact_host_list_sync_is_verified_https_fail_closed():
    assert 'URLSessionConfiguration.ephemeral' in SYNC
    assert 'url.scheme = "https"' in SYNC
    assert 'url.path = "/v1/smart/policy"' in SYNC
    assert 'request.httpMethod = "PUT"' in SYNC
    assert 'statusCode == 200' in SYNC
    assert 'receipt.ok && receipt.count == domains.count' in SYNC
    assert 'Set(hosts.filter(SiteDependencyDiscovery.isScannableHost))' in POLICY
    assert 'SiteExclusionPolicy.routingHosts(for: $0)' in POLICY
