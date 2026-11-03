"""Exact-host DIRECT proof must never degrade into an IP-wide or fake passing test.

Production consumer iOS exact-host egress must remain fail-closed; TN3120
warns about alternate-interface packet forwarding, and App Review alone
decides platform admissibility. This is a source and physical safety gate.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios"
FETCH = (IOS / "Tools/fetch_tun2proxy.py").read_text()
RETRY = (IOS / "Tools/tun2proxy-sameflow-scoped-retry.patch").read_text()
SCOPED = (IOS / "Tools/tun2proxy-experimental-scoped-direct.patch").read_text()
FAMILY = (IOS / "Tools/tun2proxy-prefer-ipv4-physical-family.patch").read_text()
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
    assert 'DIRECT_FAMILY_PATCH = TOOLS' in FETCH
    assert FETCH.index('str(SAME_FLOW_RETRY_PATCH), cwd=source)') < FETCH.index(
        'str(DIRECT_FAMILY_PATCH), cwd=source)')
    assert "values.filter(|v|physical_direct_eligible(*v))" in FAMILY
    assert "addr.is_ipv4() && public(addr.ip())" in FAMILY
    assert "ipv6_only_direct_must_fail_closed_after_real_iphone_tls_stall" in FAMILY
    assert 'if peer.is_ipv4(){10}else{11}' in FAMILY
    assert '0..=12' in FAMILY
    assert 'flow_events::emit(domain_name.as_deref(), flow_events::next_id(), 12)' in FAMILY
    assert 'domain_name.as_deref().is_some_and(crate::flow_routing::is_armed)' in FAMILY
    assert 'event == 12, self.labScopedDirect' in COLLECTOR
    assert 'lab opaque udp engine proxy path' in COLLECTOR
    assert "lab physical tcp ipv4" in COLLECTOR
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


def test_release_enabled_only_for_exact_virtual_host_without_ipwide_route():
    assert "iosPacketTunnelExactHostDirect = true" in CAPS
    assert "iosIndependentNoProxyProbe = true" in CAPS
    assert "--experimental-scoped-direct" in PROVIDER
    assert "#if DEBUG" in PROVIDER
    assert "if exactHostDirect { args +=" in PROVIDER
    assert "let exactHostDirect = AdaptiveRouteCapabilities.iosPacketTunnelExactHostDirect || physicalLab" in PROVIDER
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
    assert "event == 5, self.exactHostDirect" in COLLECTOR
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

def test_real_safari_redirect_uses_actual_browser_without_app_priming():
    app = (IOS / "App/AppViewModel.swift").read_text()
    fixture = (ROOT / "scripts/qa_smart3_scoped_direct_proxy.py").read_text()
    assert '"-aplSmart3SafariRedirectQA"' in app
    assert "UIApplication.shared.open(url, options:" in app
    assert 'if safariRedirectLab {' in app and 'else if ProcessInfo.processInfo.arguments.contains("-aplSmart3LocalProxyQA")' in app
    assert 'let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")' in HARDWARE
    assert 'testSafariHTTPRedirectRecoversAuthLikeHostWithoutReload' in HARDWARE
    assert 'hierarchy.contains("apple.com")' in HARDWARE
    assert 'label CONTAINS[c] %@' in HARDWARE and '"iPhone"' in HARDWARE
    assert 'START = "start.qa-example.test:80"' in fixture
    assert 'Location: https://www.apple.com/' in fixture
    assert '"--safari-redirect"' in fixture
    assert 'socket.create_connection(' not in fixture

def test_shared_cdn_peer_is_always_proxy_with_hardware_assertions():
    fixture = (ROOT / "scripts/qa_smart3_scoped_direct_proxy.py").read_text()
    assert 'NEIGHBOR = "www.apple.com.cn:443"' in fixture
    assert '"--shared-ip-qa"' in fixture
    assert "NEIGHBOR_PROXY_CONNECT" in fixture
    assert 'lab neighbor via proxy' in COLLECTOR
    assert 'www.apple.com.cn' in CLIENT
    assert '-aplSmart3SharedIPLabQA' in CLIENT
    assert 'testSharedCDNHostIsNotBypassedByAHostRule' in HARDWARE
    assert 'lab direct server bytes' in HARDWARE
    assert 'lab neighbor via proxy' in HARDWARE
