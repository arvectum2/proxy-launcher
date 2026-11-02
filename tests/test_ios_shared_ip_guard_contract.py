"""Guard against regressions that silently re-enable IP-wide Smart bypass.

Runtime/network safety is tested by Swift Core tests and a separate loopback
TCP experiment. These are source-wiring assertions, not device-VPN proof.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKET = (ROOT / 'mobile/ios/PacketTunnel/PacketTunnelProvider.swift').read_text()
PLAN = (ROOT / 'mobile/ios/SharedCore/SharedIPRouteGuard.swift').read_text()


def test_network_extension_routes_use_actual_guarded_plan_not_raw_resolver():
    start = PACKET.index('    private func resolveExclusions(')
    end = PACKET.index('    private func networkSettings(', start)
    body = PACKET[start:end]
    assert 'SharedIPRouteGuard.plan(approved: approved, nonApproved: denied)' in body
    assert 'let refused = store.smartGraph.pruned().edges' in body
    assert '.filter { $0.decision != .approved }' in body
    assert 'Set(refused).subtracting(approved.keys)' in body
    assert 'if candidates.count > SiteExclusionPolicy.maxEntries' in body
    assert 'denied["unverified-over-cap.example.invalid"] = nil' in body
    assert 'addresses = Set(guarded.allowedAddresses)' in body
    assert 'dnsBypass: guarded.dnsBypass' in body
    assert 'for address in resolved {' not in body  # old unguarded /32 loop


def test_guard_requires_all_host_addresses_safe_and_ipv6_canonicalization():
    assert 'addresses.allSatisfy { !withheld.contains($0) }' in PLAN
    assert 'inet_pton(AF_INET6' in PLAN
    assert 'inet_ntop(AF_INET6' in PLAN
    assert 'nonApproved.values.contains' not in PLAN  # canonicalized values only
    assert 'normalizedDenied.values.contains' in PLAN


def test_clearly_keeps_exact_host_runtime_as_separate_unfinished_milestone():
    doc = (ROOT / 'docs/APL_IOS_SMART_EXCLUSIONS_2_2026-10-31.md').read_text()
    assert 'Phase C' in doc and 'CDN' in doc
