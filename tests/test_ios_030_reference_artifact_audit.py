from pathlib import Path
import json,sys
import importlib.util as _pytest_import_util
import unittest as _pytest_unittest

# These fixtures run in the dedicated iOS pytest CI lane, not unittest-only Windows builds.
if _pytest_import_util.find_spec("pytest") is None:
    raise _pytest_unittest.SkipTest("pytest-only iOS contract; run the iOS pytest CI lane")
import pytest
T=Path(__file__).resolve().parents[1]/'mobile/ios/Tools';sys.path.insert(0,str(T))
import unified_synthetic_fixture as f
import audit_reference_peer_artifacts as a
from validate_unified_synthetic_receipt import Invalid

@pytest.mark.parametrize('kind',['wireGuard','amneziaWG1','vlessReality'])
def test_reference_artifacts_require_actual_bound_private_log(tmp_path,kind):
    root=tmp_path/'input';m=f.write(root,kind,'tcp4','positive',0xc0a80122 if kind=='amneziaWG1' else None);private=json.loads((root/'host-input.json').read_text())
    obs=tmp_path/'observer';obs.mkdir(mode=0o700)
    if kind=='wireGuard':log=b'PEER_QA_READY_server\nWG_WITNESS tcp4=1 tcp6=0 udp4=0 udp6=0 sent=4 received=4\nPEER_QA_STOPPED_server\n'
    elif kind=='amneziaWG1':log=b'AWG_PEER_READY\nAWG_WITNESS tcp4=1 tcp6=0 udp4=0 udp6=0 sent=4 received=4 rejected=0\n'
    else:log=json.dumps({**{k:m[k] for k in ('runID','candidateManifestSHA256','peerInputSHA256','challengeSHA256')},'ready':True,'stopped':True,'processExit':0,'observationClosed':True,'ingressBytes':2000,'egressBytes':1000,'witnessCount':1,'responseSHA256':f.digest(('APL_RECEIPT:'+private['nonce']).encode())}).encode()
    raw=obs/'capture.raw';raw.write_bytes(log);raw.chmod(0o600)
    prov={**{k:m[k] for k in ('runID','candidateManifestSHA256','peerInputSHA256','challengeSHA256','kind','probe','mode')},'schema':1,'scope':'independent_reference_peer','peerBinarySHA256':'a'*64,'processExit':0,'logSHA256':a.sha(log)}
    p=obs/'provenance.json';p.write_text(json.dumps(prov));p.chmod(0o600);expected=a.sha(p.read_bytes())
    out=a.audit(root,obs,expected);assert out['runtime_authorized'] is False and out['peerReceipt']['witnessCounts']['tcp4']==1
    with pytest.raises(Invalid):a.audit(root,obs,'0'*64)
    raw.write_bytes(log+b'changed')
    with pytest.raises(Invalid):a.audit(root,obs,expected)
    raw.write_bytes(log);prov['scope']='local_smoke';p.write_text(json.dumps(prov))
    with pytest.raises(Invalid):a.audit(root,obs,a.sha(p.read_bytes()))
    prov['scope']='independent_reference_peer';prov['runID']=f.uid();p.write_text(json.dumps(prov))
    with pytest.raises(Invalid):a.audit(root,obs,a.sha(p.read_bytes()))
