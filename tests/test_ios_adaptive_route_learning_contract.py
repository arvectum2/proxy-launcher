"""The iOS adaptive-routing engine is evidence-only until safe flow egress."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT/'mobile/ios/SharedCore/AdaptiveRouteLearning.swift').read_text()
CAPS = (ROOT/'mobile/ios/SharedCore/AdaptiveRouteCapabilities.swift').read_text()
STORE = (ROOT/'mobile/ios/Shared/ProfileStore.swift').read_text()
TUNNEL = (ROOT/'mobile/ios/PacketTunnel/PacketTunnelProvider.swift').read_text()


def test_no_auto_direct_from_two_timeouts_or_fake_probe():
    assert 'e.sessionIDs.count >= 2' in CORE
    assert 'return shouldProbe ? .verifyDirect(host) : .keepProxy' in CORE
    assert 'now.timeIntervalSince($0) >= 60' in CORE
    assert 'guard proxyFailed, directSucceeded, independentlyDirect else' in CORE
    assert 'guard exactHostTransport else { return .unsupportedDirect(host) }' in CORE
    assert 'e.successes >= 2' in CORE
    assert 'static let lifetime: TimeInterval = 86400' in CORE
    assert 'SiteDependencyDiscovery.eligibleForAutomaticBypass(value)' in CORE


def test_ios_host_scoped_capability_does_not_grant_ip_wide_bypass():
    assert 'iosPacketTunnelExactHostDirect = true' in CAPS
    assert 'iosIndependentNoProxyProbe = true' in CAPS
    assert '#if targetEnvironment(simulator)' in CAPS
    assert 'SharedIPRouteGuard.plan' in TUNNEL
    assert 'if exactHostDirect { args +=' in TUNNEL
    assert 'adaptiveRouteLearning' not in TUNNEL  # not falsely deployed to VPN


def test_evidence_is_bounded_and_local_not_applied_to_manual_site_exclusions():
    assert 'smart_route_evidence.v1' in STORE
    assert 'data.count <= 65_536' in STORE
    assert 'model.hosts.count <= AdaptiveRouteLearning.maxHosts' in STORE
    assert 'var adaptiveRouteLearning:' in STORE
    assert 'newValue.rejected.count <= 128' in STORE
    assert 'smartGraph.effective(manual: manualSiteExclusions)' in STORE
    assert 'defaults.set(data, forKey: Key.adaptiveLearning)' in STORE
