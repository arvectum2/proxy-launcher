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


OPAQUE_EVENTS = [
    'lab scoped probe started', 'lab direct armed',
    'lab sameflow recovered', 'lab sameflow tls data',
    'lab sameflow recovered', 'lab sameflow tls data',
    'lab physical tcp ipv4', 'lab physical tcp ipv4',
    'lab physical tcp ipv4', 'lab raw ip proxy tcp ready',
    'lab doh endpoint proxy tcp ready', 'lab opaque udp submitted',
    'lab scoped tls data',
]
OPAQUE_MOCK = ('READY_SCOPED_MOCK lifetime<=115s no_forwarding=true\\n'
               'BLOCKED_CONNECT\\nBLOCKED_CONNECT\\nHEALTHY_CONNECT\\n'
               'RAW_IP_PROXY_CONNECT\\nDOH_ENDPOINT_PROXY_CONNECT\\n')


def test_physical_opaque_raw_ip_and_doh_endpoints_stay_proxied(tmp_path):
    p, q = sample(tmp_path, names=OPAQUE_EVENTS, proxy=OPAQUE_MOCK)
    result = MOD.verify_opaque_flows(p, q)
    assert result['raw_ip_upstream_connects'] == 1
    assert result['doh_endpoint_upstream_connects'] == 1
    assert result['physical_direct_ipv6_sockets'] == 0
    assert result['udp_test_datagrams_submitted'] == 1


@pytest.mark.parametrize('drop,reason', [
    ('lab raw ip proxy tcp ready', 'lab raw ip proxy tcp ready'),
    ('lab doh endpoint proxy tcp ready', 'lab doh endpoint proxy tcp ready'),
    ('lab opaque udp submitted', 'lab opaque udp submitted'),
])
def test_opaque_evidence_requires_each_independent_device_event(tmp_path, drop, reason):
    p,q=sample(tmp_path, names=[x for x in OPAQUE_EVENTS if x!=drop], proxy=OPAQUE_MOCK)
    with pytest.raises(ValueError, match=reason):
        MOD.verify_opaque_flows(p,q)


def test_opaque_raw_ip_can_never_count_as_safe_without_proxy_connect(tmp_path):
    p,q=sample(tmp_path,names=OPAQUE_EVENTS,proxy=OPAQUE_MOCK.replace('RAW_IP_PROXY_CONNECT',''))
    with pytest.raises(ValueError,match='RAW_IP_PROXY_CONNECT'):
        MOD.verify_opaque_flows(p,q)


def test_opaque_report_rejects_ipv6_direct_sockets(tmp_path):
    p,q=sample(tmp_path,names=OPAQUE_EVENTS+['lab physical tcp ipv6'],proxy=OPAQUE_MOCK)
    with pytest.raises(ValueError,match='Unapproved IPv6'):
        MOD.verify_opaque_flows(p,q)


QUIC_EVENTS = [
    'lab direct armed', 'lab sameflow recovered', 'lab sameflow recovered',
    'lab sameflow tls data', 'lab sameflow tls data',
    'lab direct server bytes', 'lab direct server bytes',
    'lab physical tcp ipv4', 'lab physical tcp ipv4', 'lab physical tcp ipv4',
    'lab scoped tls data', 'lab raw ip proxy tcp ready',
    'lab doh endpoint proxy tcp ready', 'lab opaque quic started',
    'lab opaque udp engine proxy path',
]


def test_actual_quic_engine_udp_proxy_path_proven(tmp_path):
    p,q=sample(tmp_path,names=QUIC_EVENTS,proxy=OPAQUE_MOCK)
    r=MOD.verify_real_quic_fail_closed(p,q)
    assert r['quic_network_framework_starts']==1
    assert r['quic_packets_observed_by_udp_engine']==1


def test_quic_app_start_is_not_sufficient_without_engine_side_udp(tmp_path):
    p,q=sample(tmp_path,names=[n for n in QUIC_EVENTS if n!='lab opaque udp engine proxy path'],proxy=OPAQUE_MOCK)
    with pytest.raises(ValueError,match='lab opaque udp engine proxy path'):
        MOD.verify_real_quic_fail_closed(p,q)


def test_quic_opaque_endpoint_must_stay_on_proxy(tmp_path):
    p,q=sample(tmp_path,names=QUIC_EVENTS,proxy=OPAQUE_MOCK.replace('DOH_ENDPOINT_PROXY_CONNECT',''))
    with pytest.raises(ValueError,match='DOH_ENDPOINT_PROXY_CONNECT'):
        MOD.verify_real_quic_fail_closed(p,q)


def test_quic_bounded_evidence_allows_evicted_armed_event(tmp_path):
    names=[x for x in QUIC_EVENTS if x != 'lab direct armed']
    p,q=sample(tmp_path,names=names,proxy=OPAQUE_MOCK)
    result=MOD.verify_real_quic_fail_closed(p,q)
    assert result['original_tls_responses']==2


def test_quic_cannot_pass_without_two_recovered_original_tcp_streams(tmp_path):
    names=[x for x in QUIC_EVENTS if x != 'lab sameflow recovered']
    p,q=sample(tmp_path,names=names,proxy=OPAQUE_MOCK)
    with pytest.raises(ValueError,match='lab sameflow recovered'):
        MOD.verify_real_quic_fail_closed(p,q)
