"""Guard live per-host TCP observation without unsanctioned iOS DIRECT."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATCH = (ROOT/'mobile/ios/Tools/tun2proxy-flow-intent.patch').read_text()
FETCH = (ROOT/'mobile/ios/Tools/fetch_tun2proxy.py').read_text()
PROVIDER = (ROOT/'mobile/ios/PacketTunnel/PacketTunnelProvider.swift').read_text()
COLLECTOR = (ROOT/'mobile/ios/PacketTunnel/SmartFlowEventCollector.swift').read_text()
VIEW = (ROOT/'mobile/ios/App/ExclusionsView.swift').read_text()


def test_real_virtual_dns_flow_events_no_untrusted_sni_fallback():
    assert 'let observed_host = domain_name.clone();' in PATCH
    assert 'let observed_id = flow_events::next_id();' in PATCH
    assert 'mod flow_events;' in PATCH
    assert 'Ok(Ok(_)) => flow_events::emit(observed_host, observed_id, 0)' in PATCH
    assert 'flow_events::emit(observed_host, observed_id, 4);' in PATCH
    assert 'std::time::Duration::from_secs(12)' in PATCH
    assert 'validate_exact_host(host).ok()' in PATCH
    assert 'tun2proxy_set_flow_event_callback' in PATCH
    assert 'io.kind()' not in PATCH or 'TimedOut' in PATCH


def test_pinned_rebuild_includes_added_abi_and_ios_lifecycle():
    assert 'install_flow_event_header(source_framework)' in FETCH
    assert 'git", "apply", "--check", str(FLOW_INTENT_PATCH)' in FETCH
    assert 'SmartFlowEventCollector.shared.start(store: store,' in PROVIDER
    assert 'exactHostDirect: exactHostDirect, labScopedDirect: physicalLab' in PROVIDER
    assert 'SmartFlowEventCollector.shared.stop()' in PROVIDER
    assert 'tun2proxy_set_flow_event_callback(nil, nil)' in COLLECTOR
    assert 'self.successfulHosts.contains { $0.key != host }' in COLLECTOR
    assert 'store.adaptiveRouteLearning = learning' in COLLECTOR
    assert 'event == 1 || event == 2' in COLLECTOR


def test_live_ui_requires_explicit_consent_never_autobypasses_ip():
    assert 'diagnosticHints = model.adaptiveRouteLearning.diagnosticCandidates()' in VIEW
    assert 'pendingExternalHost = host' in VIEW
    assert 'confirmExternal = true' in VIEW
    assert 'Общий IP-адрес может обслуживать и другие сайты' in VIEW
    assert 'automaticallyIncluded' in VIEW
    assert 'SmartFlowEventCollector.shared' not in VIEW
    assert 'networkSettings(excludedAddresses: exclusions.addresses)' in PROVIDER
    assert 'adaptiveRouteLearning' not in PROVIDER
