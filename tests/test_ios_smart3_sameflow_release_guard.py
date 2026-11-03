"""Exact-host DIRECT proof must never degrade into an IP-wide or fake passing test.

Production consumer iOS cannot enable this experimental alternate egress under
Apple TN3120 without separate platform support. This is a source safety gate,
not an assertion that Safari zero-touch recovery is App Store ready.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios"
FETCH = (IOS / "Tools/fetch_tun2proxy.py").read_text()
RETRY = (IOS / "Tools/tun2proxy-sameflow-scoped-retry.patch").read_text()
SCOPED = (IOS / "Tools/tun2proxy-experimental-scoped-direct.patch").read_text()
PROVIDER = (IOS / "PacketTunnel/PacketTunnelProvider.swift").read_text()
COLLECTOR = (IOS / "PacketTunnel/SmartFlowEventCollector.swift").read_text()
HARDWARE = (IOS / "Tests/UITests/Smart3LiveTunnelPhysicalUITests.swift").read_text()
CLIENT = (IOS / "App/Smart3PhysicalTrafficQA.swift").read_text()
CAPS = (IOS / "SharedCore/AdaptiveRouteCapabilities.swift").read_text()


def test_pinned_replay_order_and_same_captured_tcp_stream():
    assert "SAME_FLOW_RETRY_PATCH = TOOLS" in FETCH
    assert FETCH.index('str(SCOPED_DIRECT_EXPERIMENT_PATCH), cwd=source)') < FETCH.index(
        'str(SAME_FLOW_RETRY_PATCH), cwd=source)'
    )
    assert "recover_after_proxy_failure" in RETRY
    assert "if lab_direct && direct_host.is_none()" in RETRY or (
        'lab_direct && direct_host.is_none()' in RETRY)
    assert "flow_routing::is_armed" in RETRY
    assert "server = direct;" in RETRY
    assert "tcp_stack" in RETRY
    assert "observed_id, 7" in RETRY
    assert "0..=9" in RETRY
    assert "tokio::time::sleep" in RETRY
    assert "Duration::from_secs(5)" in RETRY


def test_direct_cannot_be_enabled_by_default_or_raw_ip():
    assert "iosPacketTunnelExactHostDirect = false" in CAPS
    assert "iosIndependentNoProxyProbe = false" in CAPS
    assert "--experimental-scoped-direct" in PROVIDER
    assert "#if DEBUG" in PROVIDER
    assert "if qaScopedDirect { args +=" in PROVIDER
    assert "experimental_scoped_direct: false" in SCOPED
    assert "if !valid_fake { return FlowIntent::Proxy; }" in SCOPED
    assert 'FlowIntent::Proxy' in SCOPED
    assert 'NEIPv4Route(' not in RETRY
    assert "IP_BOUND_IF" in SCOPED


def test_physical_qa_requires_real_socket_and_original_tls_payload():
    assert '["APL_SMART3_SCOPED_QA"] == "enabled"' in HARDWARE
    assert 'Thread.sleep(forTimeInterval: 23)' in HARDWARE
    assert "lab scoped tcp connected" in HARDWARE
    assert "lab scoped tls data" in HARDWARE
    assert "lab sameflow recovered" in HARDWARE
    assert "lab sameflow tls data" in HARDWARE
    assert 'XCTAssertTrue(recovered.waitForExistence' in HARDWARE
    assert 'XCTAssertTrue(originalData.waitForExistence' in HARDWARE
    assert 'labDirect ? .tls : .tcp' in CLIENT
    assert 'lab sameflow tls data' in CLIENT
    assert "event == 7, self.labScopedDirect" in COLLECTOR
    assert "event == 5, self.labScopedDirect" in COLLECTOR
    assert 'tun2proxy_set_direct_exact_host($0, false)' in COLLECTOR


def test_lan_mock_is_explicit_and_never_forwards_any_destination():
    fixture = (ROOT / "scripts/qa_smart3_scoped_direct_proxy.py").read_text()
    assert 'if not options.physical_lab:' in fixture
    assert 'Only explicit private IPv4 LAN binding is permitted.' in fixture
    assert 'HEALTHY = "www.cloudflare.com:443"' in fixture
    assert 'FAIL = "www.apple.com:443"' in fixture
    assert 'time.sleep(13.8)' in fixture
    assert 'threading.Timer(115, server.shutdown)' in fixture
    assert 'no_forwarding=true' in fixture
    assert 'socket.create_connection(' not in fixture
    assert 'socket.socket(' not in fixture
    assert 'HTTP/1.1 403 Forbidden' in fixture
