"""Protect the original-flow test-only CONNECT instrumentation."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PT = ROOT / "mobile/ios/PacketTunnel/PacketTunnelProvider.swift"
COLL = ROOT / "mobile/ios/PacketTunnel/SmartFlowEventCollector.swift"
QA = ROOT / "mobile/ios/Tests/DeviceKeychainTests/PhysicalProxyConnectOutcomeTests.swift"


def test_debug_only_opt_in_and_bounded_native_outcome_budget():
    p,c,q = PT.read_text(), COLL.read_text(), QA.read_text()
    assert '#if DEBUG' in p and 'stopAfter == 25' in p
    assert 'qaTracePublicIPv4Only' in p and 'qaTracePublicIPv4Only' in c
    assert 'host == "ipv4.icanhazip.com"' in c
    assert '(0...4).contains(event)' in c
    assert 'self.qaTracePublicIPv4Budget < 8' in c
    assert 'type: "qa ipv4-only proxy connect outcome"' in c
    assert '#if APL_RUN_EXPLICIT_VPN_QA' in q
    assert '#if targetEnvironment(simulator)' in q
    assert '"qaStopAfterSeconds": NSNumber(value: 25)' in q
    assert 'deadline: .now() + 20' in q
    assert 'manager.connection.status == .disconnected' in q
    assert 'tunnel.stopVPNTunnel()' in q


def test_no_credentials_ip_or_private_raw_error_diagnostics():
    all_src = PT.read_text() + COLL.read_text() + QA.read_text()
    qa = QA.read_text()
    for forbidden in (
        'print(tunnel', 'print(manager', 'print(events',
        'print($0.detail', 'print(error', 'print(profile', 'print(password',
        'String(describing: error)', 'saveToPreferences', 'removeFromPreferences',
        'SecItemAdd', 'SecItemDelete',
    ):
        assert forbidden not in qa
    assert 'detail: "native_code=' in all_src
    assert 'qaTracePublicIPv4Only = false' in all_src
