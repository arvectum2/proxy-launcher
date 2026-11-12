"""Opt-in real iPhone disposable IPv6-destination PacketTunnel QA safety."""
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "mobile/ios/Tests/DeviceKeychainTests/PhysicalDisposableIPv6UpstreamTests.swift"


def test_explicit_flag_original_off_with_two_independent_stop_guards():
    s = P.read_text()
    assert "#if APL_RUN_EXPLICIT_VPN_QA" in s
    assert "#if targetEnvironment(simulator)" in s
    assert "NETunnelProviderManager.loadAllFromPreferences" in s
    assert "manager.connection.status == .disconnected" in s
    assert "qaSmart3ProxyHost" in s and '"192.168.1.80"' in s
    assert "qaSmart3ProxyPort" in s and "18081" in s
    assert '"qaStopAfterSeconds": NSNumber(value: 25)' in s
    assert 'deadline: .now() + 20' in s
    assert "tunnel.stopVPNTunnel()" in s
    assert "disposable.allowFailover = false" in s
    assert "matchesProxy" in s and "XCTAssertTrue(restored" in s


def test_evidence_does_not_log_ip_or_mutate_owner_data():
    s = P.read_text()
    assert 'inet_pton(AF_INET6' in s
    for forbidden in (
        "saveToPreferences", "removeFromPreferences", "SecItemAdd", "SecItemDelete",
        "store.save(", "print(origin", "print(throughVPN", "print(before", "print(control",
        "print(manager", "print(profile", "print(password", "print(error",
        "String(describing: error)", "setAllowsAnyHTTPSCertificate",
    ):
        assert forbidden not in s


def test_native_ipv6_packet_qa_requires_explicit_validated_tls_hostname():
    s = P.read_text()
    assert 'testBoundedPacketTunnelNativeIPv6TLSPacketViaDisposableProxy' in s
    assert 'NWEndpoint.Host.ipv6(IPv6Address("2606:4700:4700::1111")!)' in s
    assert 'sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, "one.one.one.one")' in s
    assert 'nativeIPv6TLS()' in s
    assert 'APL_V6_NATIVE_TUN_LITERAL_IPV6_TLS_HTTP200_' in s
    assert 'APL_V6_NATIVE_TUN_DIRECT_IPV6_SNI_TLS_RESTORED_' in s
    assert 'tunnel.stopVPNTunnel()' in s
    assert 'qaSmart3ProxyHost' in s and 'qaStopAfterSeconds' in s
    for forbidden in ('sec_protocol_options_set_verify_block','SecTrustSetExceptions',
                      'allowInvalidCertificates','print(tls','print(origin','print(connection'):
        assert forbidden not in s
