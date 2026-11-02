"""Pinned experimental source patch must stay fail-closed in iOS release.

Executable Rust behaviour is validated separately by cargo test --lib. This
contract guards the future regeneration script against disabling the gate.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'mobile/ios/Tools'
FETCH = (TOOLS/'fetch_tun2proxy.py').read_text()
PATCH = (TOOLS/'tun2proxy-flow-intent.patch').read_text()
TUNNEL = (ROOT/'mobile/ios/PacketTunnel/PacketTunnelProvider.swift').read_text()


def test_second_patch_is_pinned_applied_after_legacy_dns_patch():
    assert 'SOURCE_COMMIT = "e271de19683937f23d3f8f0eb4df0a61fc4a6e50"' in FETCH
    assert 'FLOW_INTENT_PATCH = TOOLS / "tun2proxy-flow-intent.patch"' in FETCH
    assert 'git", "apply", "--check", str(FLOW_INTENT_PATCH)' in FETCH
    assert FETCH.index('str(SPLIT_DNS_PATCH), cwd=source)') < FETCH.index('str(FLOW_INTENT_PATCH), cwd=source)')
    assert 'split-dns-and-flow-intent' in FETCH


def test_flow_policy_does_not_open_unsupported_direct_socket():
    assert 'DirectNeedsScopedTransport' in PATCH
    assert 'FlowIntent::Proxy' in PATCH
    assert 'mgr.new_proxy_handler(info, domain_name, false).await?' in PATCH
    assert 'scoped transport unavailable' not in PATCH or 'upstream PROXY' in PATCH
    assert 'new_proxy_handler(info, domain_name, false)' in PATCH
    assert 'NoProxyManager::new' not in PATCH
    assert 'TcpStream::connect' not in PATCH
    assert 'NWListener' not in PATCH
    assert 'for_new_flow(domain_name.as_deref(), tcp.peer_addr().ip())' in PATCH
    assert '--flow-direct-candidate' not in TUNNEL
    assert '--dns-bypass' in TUNNEL  # legacy IP-wide risk still explicit


def test_release_adr_explicitly_marks_full_goal_blocked():
    doc=(ROOT/'docs/APL_SMART_FLOW_PER_CONNECTION_ADR_2026-11-02.md').read_text()
    assert 'TN3120' in doc
    assert 'НЕ реализован' in doc or 'НЕ активирован' in doc
    assert 'blocked' in doc
    assert 'два TLS-hosts' in doc
