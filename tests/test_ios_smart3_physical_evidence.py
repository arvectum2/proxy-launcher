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
