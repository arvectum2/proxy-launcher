"""Signed-device QA safety contract; no real device execution."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "mobile/ios/Tests/DeviceKeychainTests/PhysicalDisposableIPv6UpstreamTests.swift"


def test_udp_qa_requires_opt_in_public_ipv6_before_starting_any_vpn():
    text = PROBE.read_text()
    method = text.split("func testBoundedUDPDirectWitnessBlockedInPacketTunnelAndRestored()", 1)[1]
    assert '#if targetEnvironment(simulator)' in method
    assert 'env["APL_QA_UDP_ENABLE"] == "YES"' in method
    assert 'env["APL_QA_UDP_WITNESS_IPV6"]' in method
    assert 'env["APL_QA_UDP_WITNESS_PORT"]' in method
    assert "portNumber >= 1024" in method
    assert "inet_pton(AF_INET6" in method
    assert "bytes[0] & 0xe0" in method
    assert method.index('env["APL_QA_UDP_ENABLE"]') < method.index("existingOffTunnel()")
    assert method.index('existingOffTunnel()') < method.index("tunnel.startTunnel(options:")


def test_no_owner_proxy_usage_or_backup_changes_and_bounded_stop():
    text = PROBE.read_text()
    method = text.split("func testBoundedUDPDirectWitnessBlockedInPacketTunnelAndRestored()", 1)[1]
    assert 'await udpEcho(witness, port: port)' in method
    assert 'labProxy.allowFailover = false' in method
    assert 'ipv6Witness(labProxy)' in method
    assert '(try? await ipv6Witness(nil)) == labOrigin' in method
    assert '"qaSmart3ProxyHost": "192.168.1.80"' in method
    assert '"qaSmart3ProxyPort": NSNumber(value: 18081)' in method
    assert '"qaStopAfterSeconds": NSNumber(value: 25)' in method
    assert "deadline: .now() + 20" in method
    assert "tunnel.stopVPNTunnel()" in method
    assert "XCTAssertFalse(escaped" in method
    assert "XCTAssertTrue(restored" in method
    for forbidden in ("saveToPreferences", "removeFromPreferences",
                      "SecItemDelete", "SecItemAdd", "store.save(",
                      "print(host", "print(token", "print(witness",
                      "print(labOrigin", "print(profile", "print(password"):
        assert forbidden not in method


def test_echo_uses_single_nonce_unchanged_and_bounded_network_connection():
    text = PROBE.read_text()
    snippet = text.split("private func udpEcho(", 1)[1].split(
        "func testBoundedUDPDirectWitnessBlockedInPacketTunnelAndRestored()", 1)[0]
    assert '"APL030-" + UUID().uuidString' in snippet
    assert "connection.send(content: token" in snippet
    assert "response == token" in snippet
    assert "deadline: .now() + 2.5" in snippet
    assert "Once()" in snippet and "connection.cancel()" in snippet
