"""Hardware tests are opt-in and do not silently leak user traffic/settings."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'mobile/ios'


def test_hardware_qa_is_synthetic_only_and_self_terminating():
    driver = (SRC/'App/Smart3PhysicalTrafficQA.swift').read_text()
    tunnel = (SRC/'PacketTunnel/PacketTunnelProvider.swift').read_text()
    vpn = (SRC/'App/VPNController.swift').read_text()
    test = (SRC/'Tests/UITests/Smart3LiveTunnelPhysicalUITests.swift').read_text()
    assert 'probe.qa-example.test' in driver and driver.count('auth.qa-example.test') == 2
    assert 'www.apple.com' not in driver and 'www.cloudflare.com' not in driver
    assert '#if DEBUG' in driver and '#if DEBUG' in tunnel and '#if DEBUG' in vpn
    assert 'qaStopAfterSeconds' in tunnel and 'cancelTunnelWithError' in tunnel
    assert 'qaStopAfterSeconds' in vpn
    assert 'APL_SMART3_HARDWARE_QA' in test
    assert 'throw XCTSkip' in test
    assert 'testLiveVPTunnelPerHostCONNECTSignalWithAutoRollback' in test


def test_physical_probe_is_diagnostic_not_proof_of_noproxy():
    probe = (SRC/'App/AdaptiveDirectProbe.swift').read_text()
    view = (SRC/'App/ExclusionsView.swift').read_text()
    test = (SRC/'Tests/UITests/AdaptiveDirectProbePhysicalUITests.swift').read_text()
    assert 'requiredInterfaceType' in probe
    assert 'currentPath?.usesInterfaceType' in probe
    assert 'TLS' in probe
    assert 'маршрут не подтверждён' in view
    assert 'APL_SMART3_HARDWARE_QA' in test
    assert 'testPhysicalTLSProbeDisplaysBoundedDiagnostic' in test
    assert 'no-proxy' not in probe.lower() or 'NOT' in probe


def test_synthetic_evidence_can_only_be_cleared_when_no_real_hosts_exist():
    store = (SRC/'Shared/ProfileStore.swift').read_text()
    viewmodel = (SRC/'App/AppViewModel.swift').read_text()
    assert 'clearSyntheticSmart3QAEvidence' in store
    assert 'state.hosts.keys.allSatisfy({ $0.hasSuffix(".qa-example.test") })' in store
    assert 'state.rejected.isEmpty' in store
    assert 'defaults.removeObject(forKey: Key.adaptiveLearning)' in store
    assert 'aplSmart3CleanQAOnlyEvidence' in viewmodel
    assert 'store.clearSyntheticSmart3QAEvidence()' in viewmodel


def test_bounded_proxy_qa_script_never_forwards_external_destinations():
    qa = (ROOT/'scripts/qa_smart3_local_proxy.py').read_text()
    assert 'auth.qa-example.test:443' in qa and 'probe.qa-example.test:443' in qa
    assert 'time.sleep(13.8)' in qa
    assert 'threading.Timer(115, server.shutdown)' in qa
    assert 'HTTP/1.1 403 Forbidden' in qa
    assert 'socket.create_connection' not in qa
