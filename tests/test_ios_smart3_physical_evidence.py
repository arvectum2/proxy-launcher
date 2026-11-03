"""Conservative independent evidence gate for physical same-CDN QA."""
import importlib.util
import json
import plistlib
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('smart3_evidence', ROOT/'scripts/qa_smart3_physical_evidence.py')
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)
NAMES = ['lab scoped enabled','lab scoped probe started','lab scoped probe results',
         'lab direct armed','lab sameflow recovered','lab direct client bytes',
         'lab direct server bytes','lab sameflow tls data',
         'lab sameflow recovered','lab direct client bytes','lab direct server bytes',
         'lab sameflow tls data','lab scoped tls data','lab neighbor tcp ready',
         'lab neighbor via proxy']


def sample(tmp_path, names=NAMES, proxy='BLOCKED_CONNECT\nBLOCKED_CONNECT\nHEALTHY_CONNECT\nNEIGHBOR_PROXY_CONNECT\n'):
    p=tmp_path/'group.plist'; q=tmp_path/'proxy.log'
    p.write_bytes(plistlib.dumps({'tunnel_events_v1':json.dumps([
        {'timestamp':float(i+1),'type':name} for i,name in enumerate(names)
    ]).encode(),'private_token':'never print me'}));q.write_text(proxy)
    return p,q


def test_physical_evidence_accepts_complete_two_sided_proof(tmp_path):
    p,q=sample(tmp_path); d=MOD.verify_shared_ip(p,q)
    assert d['neighbor_proxy_connects']==1 and d['original_tls_responses']==2


def test_cannot_claim_pass_when_neighbor_not_proxied(tmp_path):
    p,q=sample(tmp_path,proxy='BLOCKED_CONNECT\nBLOCKED_CONNECT\nHEALTHY_CONNECT\n')
    with pytest.raises(ValueError,match='NEIGHBOR_PROXY_CONNECT'): MOD.verify_shared_ip(p,q)


def test_cannot_claim_pass_without_original_tls_response(tmp_path):
    p,q=sample(tmp_path,names=[x for x in NAMES if x!='lab sameflow tls data'])
    with pytest.raises(ValueError,match='lab sameflow tls data'): MOD.verify_shared_ip(p,q)


IPV6_SAFE_EVENTS = [
    'lab scoped probe started', 'lab scoped probe results',
    'lab direct armed', 'lab direct reverted',
    'lab scoped tls attempt', 'lab ipv6 neighbor via proxy',
    'lab ipv6 neighbor tcp ready',
]
IPV6_SAFE_PROXY = (
    'BLOCKED_CONNECT\nBLOCKED_CONNECT\nHEALTHY_CONNECT\n'
    'IPV6_NEIGHBOR_PROXY_CONNECT\n'
)


def test_real_ipv6_unverified_scoped_transport_must_fail_closed(tmp_path):
    p, q = sample(tmp_path, names=IPV6_SAFE_EVENTS, proxy=IPV6_SAFE_PROXY)
    result = MOD.verify_ipv6_fail_closed(p, q)
    assert result['outgoing_direct_ipv6_sockets'] == 0
    assert result['direct_tls_responses'] == 0
    assert result['ipv6_neighbor_proxy_connects'] == 1


def test_ipv6_physical_tcp_attempt_can_never_be_mistaken_for_safe_fallback(tmp_path):
    p, q = sample(tmp_path,
                  names=IPV6_SAFE_EVENTS + ['lab physical tcp ipv6'],
                  proxy=IPV6_SAFE_PROXY)
    with pytest.raises(ValueError, match='IPv6-only host escaped fail-closed'):
        MOD.verify_ipv6_fail_closed(p, q)


def test_ipv6_canonical_neighbor_must_stay_on_upstream_proxy(tmp_path):
    p, q = sample(tmp_path, names=IPV6_SAFE_EVENTS,
                  proxy='BLOCKED_CONNECT\nBLOCKED_CONNECT\nHEALTHY_CONNECT\n')
    with pytest.raises(ValueError, match='neighbor bypassed upstream'):
        MOD.verify_ipv6_fail_closed(p, q)
