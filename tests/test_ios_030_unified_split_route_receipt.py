import copy,hashlib,sys
from pathlib import Path
import pytest
TOOLS=Path(__file__).resolve().parents[1]/'mobile/ios/Tools';sys.path.insert(0,str(TOOLS))
import unified_synthetic_fixture as f
import unified_split_route_fixture as s
import validate_unified_split_route_receipt as v
from validate_unified_synthetic_receipt import Invalid,validate_host

@pytest.mark.parametrize('case',['included','excluded'])
@pytest.mark.parametrize('probe',['tcp4','tcp6','udp4','udp6'])
def test_split_route_requires_matching_positive_and_independent_negative(case,probe):
    m,private,peer,witness=s.generate(case,probe,0xc0a80122);identity=m['identity'];expected=f.digest(('APL:'+private['nonce']).encode())
    h={**{k:m[k] for k in ('runID','owner','identity','fixtureSHA256','probe','mode','splitCase')},'schema':1,'responseSHA256':expected,'probeAttempted':True,'osOff':True,'exchanges':[]}
    for action,state,ident in [('observe','starting',identity),('observe','rejected',dict(identity,epoch=f.uid())),('drain','drained',identity)]:
        q={'version':1,'id':f.uid(),'identity':ident,'action':action};h['exchanges'].append({'request':q,'response':dict(q,state=state)})
    def observer(role):
        yes=(case=='included')==(role=='tunnel')
        return {**{k:m[k] for k in ('runID','candidateManifestSHA256','challengeSHA256','peerInputSHA256','splitCase','target','probe')},'schema':1,'observerID':m[role+'Observer'],'path':role,'observationClosed':True,'preflightSHA256':f.digest((role+'preflight').encode()),'captureSHA256':f.digest((role+'capture').encode()),'witnessCount':int(yes),'responseSHA256':expected if yes else None}
    t,e=observer('tunnel'),observer('external')
    assert v.validate(m,h,private,peer,witness,t,e)['runtime_authorized'] is False
    with pytest.raises(Invalid):validate_host(m,h,private)
    for changes in ({'observationClosed':False},{'observerID':e['observerID']},{'captureSHA256':e['captureSHA256']},{'target':'192.0.2.100'},{'witnessCount':2},{'responseSHA256':'0'*64}):
        with pytest.raises(Invalid):v.validate(m,h,private,peer,witness,dict(t,**changes),e)
    with pytest.raises(Invalid):v.validate(m,h,private,peer,witness,e,t)
    with pytest.raises(Invalid):v.validate(m,dict(h,responseSHA256=None),private,peer,witness,t,e)
    with pytest.raises(Invalid):v.validate(m,h,private,peer,witness,dict(t,witnessCount=0,responseSHA256=None),dict(e,witnessCount=0,responseSHA256=None))
    with pytest.raises(Invalid):v.validate(m,h,private,peer,witness,dict(t,witnessCount=1,responseSHA256=expected),dict(e,witnessCount=1,responseSHA256=expected))
    with pytest.raises(Invalid):v.validate(dict(m,candidateManifestSHA256=f.CONTAINING_CANDIDATE),h,private,peer,witness,t,e)

def test_split_candidate_is_separate_gate_and_fixed_targets(tmp_path):
    for case,probe in [('included','tcp4'),('excluded','udp6')]:
        root=tmp_path/case;m=s.write(root,case,probe,0xc0a80122);assert m['candidateManifestSHA256']==f.SPLIT_CANDIDATE
        assert all(x.stat().st_mode&0o777==0o600 for x in root.iterdir())
        with pytest.raises(FileExistsError):s.write(root,case,probe,0xc0a80122)
    assert s.target('included','tcp4')=='192.0.2.2' and s.target('excluded','udp6')=='2001:db8::3'
    with pytest.raises(ValueError):s.target('192.0.2.99','tcp4')
    assert 'APL_NATIVE_SYNTHETIC_SPLIT_ROUTE' not in (TOOLS.parent/'project.yml').read_text()
    build=(TOOLS/'build_product_unified_candidate_unsigned.sh').read_text();assert 'SPLIT_REQUIRES_ISOLATED_HOST_AND_RUNTIME' in build
    provider=(TOOLS.parent/'PacketTunnel/NativeAWGPacketSession.swift').read_text();assert 'settings=try NativeTunnelNetworkSettings.makeSyntheticSplitRoute()' in provider


def test_observation_hashes_require_actual_private_artifacts(tmp_path):
    r=tmp_path/'observer';r.mkdir(mode=0o700)
    files={'preflight.raw':b'preflight synthetic test','capture.raw':b'capture synthetic test'}
    for name,data in files.items():
        p=r/name;p.write_bytes(data);p.chmod(0o600)
    record={'preflightSHA256':f.digest(files['preflight.raw']),'captureSHA256':f.digest(files['capture.raw'])}
    v.verify_observation_files(r,record)
    (r/'capture.raw').write_bytes(b'changed')
    with pytest.raises(Invalid):v.verify_observation_files(r,record)
    (r/'capture.raw').unlink();(r/'capture.raw').symlink_to(r/'preflight.raw')
    with pytest.raises(Invalid):v.verify_observation_files(r,record)
