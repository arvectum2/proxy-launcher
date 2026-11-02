"""User intent: Add A => scan B/C, auto trust strong first-party, propose others."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / 'mobile/ios/App/ExclusionsView.swift').read_text()
SCANNER = (ROOT / 'mobile/ios/App/ExclusionWebScanner.swift').read_text()
GRAPH = (ROOT / 'mobile/ios/SharedCore/SmartExclusionGraph.swift').read_text()
DISCOVERY = (ROOT / 'mobile/ios/SharedCore/SiteDependencyDiscovery.swift').read_text()


def test_add_triggers_scan_not_manual_search_or_gateway():
    assert 'if newlyAdded { queueScan(value) }' in VIEW
    assert 'private func queueScan(' in VIEW
    assert 'private func scanNextQueuedSite()' in VIEW
    assert 'queueScan(host)' in VIEW
    assert 'guard !scanning && queuedScans.isEmpty else { return }' in VIEW
    assert 'automaticallyIncluded' in VIEW
    assert 'APL Gateway (TLS)' not in VIEW


def test_scan_both_html_actual_network_and_external_assets_without_auto_approval():
    assert "performance.getEntriesByType('resource')" in SCANNER
    assert 'externalCandidates(html: html, urls: resources, for: self.host)' in SCANNER
    assert 'DispatchQueue.main.asyncAfter(deadline: .now() + 1.2)' in SCANNER
    assert 'destinationHost == "www." + requested' in SCANNER
    assert 'externalCandidates(html: String, urls: [String], for site: String)' in DISCOVERY
    assert '.confirmationDialog(' in VIEW
    assert 'Разрешить прямой доступ для стороннего домена?' in VIEW
    assert 'Добавить проблемный сайт в обход VPN?' in VIEW


def test_auto_approval_is_strong_only_bounded_and_rejection_preserving():
    assert 'graph.approveStrongFirstParty(parent: host, manual: entries)' in VIEW
    assert 'edges[i].decision == .pending && edges[i].evidence == .both' in GRAPH
    assert 'Self.validChild(edges[i].host, for: parent)' in GRAPH
    assert 'edges[i].decision = .pending' in GRAPH
    assert 'try? effective(manual: manual, at: now)' in GRAPH
    assert 'graph.observe(parent: host, html: observation.html, network: observation.network)' in VIEW
    assert 'externalHints = observation.external.filter' in VIEW
    assert 'if discovered.isEmpty && externalHints.isEmpty && autoAdded.isEmpty' in VIEW
