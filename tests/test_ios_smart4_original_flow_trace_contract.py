"""Source fail-closed guard: native TCP event trace remains opt-in DEBUG only."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'mobile/ios/SharedCore/Smart4OriginalFlowTrace.swift'
COLLECTOR = ROOT / 'mobile/ios/PacketTunnel/SmartFlowEventCollector.swift'
PROVIDER = ROOT / 'mobile/ios/PacketTunnel/PacketTunnelProvider.swift'
NATIVE = ROOT / 'mobile/ios/Tools/tun2proxy-sameflow-scoped-retry.patch'
FAMILY = ROOT / 'mobile/ios/Tools/tun2proxy-dual-stack-physical-family.patch'


def test_only_rust_original_connection_id_and_real_first_bytes_are_considered():
    source, native, family = CORE.read_text(), NATIVE.read_text(), FAMILY.read_text()
    assert 'connectionID: UInt64' in source
    assert 'events.contains(7) && events.contains(8)' in source
    assert 'events.contains(9)' in source
    assert 'events.contains(10) != events.contains(11)' in source
    assert 'observed_id, 7' in native
    assert 'flow_events::emit(host, id, if is_tx { 8 } else { 9 })' in native
    assert 'if peer.is_ipv4(){10}else{11}' in family
    assert 'id, if is_tx { 8 } else { 9 }' in native
    assert 'externalEgressVerified = false' in source


def test_only_existing_explicit_debug_hardware_qa_enables_attribution():
    source, collector, provider = CORE.read_text(), COLLECTOR.read_text(), PROVIDER.read_text()
    assert 'if self.labScopedDirect {' in collector
    assert 'self.smart4OriginalTrace.record(host: host, connectionID: id,' in collector
    assert 'let evidence = self.smart4OriginalTrace.summary(at: now)' in collector
    assert 'evidence.conflicted == 0 && !evidence.overflowed' in collector
    assert 'external egress unverified' in collector
    assert collector.index('if self.labScopedDirect {\n                self.smart4OriginalTrace.record') > collector.index('#if DEBUG\n            // DEBUG-only')
    assert collector.index('self.smart4OriginalTrace.record') < collector.index('#endif\n            if event == 0')
    assert 'qaScopedDirect = (options?["qaScopedDirect"]' in provider
    assert 'stopAfter == 30 || radioHandoffQA' in provider
    assert 'let physicalLab = qaScopedDirect' in provider
    assert 'let physicalLab = false' in provider
    assert 'if exactHostDirect { args += " --experimental-scoped-direct" }' in provider
    assert '--flow-direct-candidate' not in provider
    for forbidden in ('UserDefaults', 'Keychain', 'SecItem', 'URLSession', 'socket(', 'getifaddrs',
                      'NWConnection(', 'tun2proxy_set_direct_exact_host(', 'NetworkExtension'):
        assert forbidden not in source


def test_bounded_never_persistent_and_same_host_alias_only():
    source = CORE.read_text()
    assert 'static let maxFlows = 32' in source
    assert 'static let lifetime: TimeInterval = 60' in source
    assert 'now < entry.last' in source
    assert 'alias != entry.alias' in source
    assert 'entry.events.contains(10) && entry.events.contains(11)' in source
    assert 'overflowed = true' in source
    assert 'flows.removeAll(keepingCapacity: false)' in source
    assert 'let externalEgressVerified = false' in source
    assert 'host: String' in source
    assert 'case "www.apple.com":' in source
    assert 'case "www.apple.com.cn":' in source
    assert 'case "ipv6.l.google.com":' in source
    assert 'case "start.qa-example.test":' in source
    assert 'print(' not in source
    assert 'TelemetryStore' not in source
    assert 'flow_direct_candidate' not in source

# Compatible with the project's unittest-only macOS/Windows CI runners.
def load_tests(loader, tests, pattern):
    import unittest
    for name, function in sorted(globals().items()):
        if name.startswith('test_') and callable(function):
            tests.addTest(unittest.FunctionTestCase(function, description=name))
    return tests
