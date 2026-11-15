import base64,copy,sys
from pathlib import Path
import pytest
TOOLS=Path(__file__).resolve().parents[1]/'mobile/ios/Tools'
sys.path.insert(0,str(TOOLS))
import unified_synthetic_fixture as f
import validate_unified_synthetic_receipt as v

@pytest.mark.parametrize('kind,probe,mode',[('wireGuard','tcp4','positive'),('wireGuard','udp6','wrong-key'),('amneziaWG1','tcp6','positive'),('amneziaWG1','udp4','wrong-psk'),('vlessReality','tcp4','positive'),('vlessReality','tcp4','wrong-key')])
def test_fixture_and_receipt_contract(kind,probe,mode):
    m,private,server=f.generate(kind,probe,mode,0xc0a80122 if kind=='amneziaWG1' else None)
    positive=mode=='positive';identity=m['identity'];receipt=f.digest((('APL:' if kind=='amneziaWG1' else 'APL_RECEIPT:')+private['nonce']).encode()) if positive else None
    fixture=base64.b64decode(private['fixture']);assert f.digest(fixture)==m['fixtureSHA256'];assert private['nonce'] not in str(m)
    if kind=='amneziaWG1':assert len(fixture)==96 and (fixture[-32:].hex()==server['PSK'])==(mode!='wrong-psk')
    if kind=='wireGuard':assert b'192.168.1.80:39881' in fixture and b'0.0.0.0/0' not in fixture
    if kind=='vlessReality':assert b'192.168.1.80:39882' in fixture and server['outbounds'][0]['protocol']=='blackhole'
    exchanges=[]
    for action,state,i in [('observe','starting',identity),('observe','rejected',dict(identity,epoch=f.uid())),('drain','drained',identity)]:
        q={'version':1,'id':f.uid(),'identity':i,'action':action};exchanges.append({'request':q,'response':dict(q,state=state)})
    h={**{k:m[k] for k in ('runID','owner','identity','fixtureSHA256','probe','mode')},'schema':1,'exchanges':exchanges,'responseSHA256':receipt,'probeAttempted':True,'osOff':True}
    p={**{k:m[k] for k in ('runID','candidateManifestSHA256','challengeSHA256','peerInputSHA256','probe','mode')},'schema':1,'observationClosed':True,'ingressPackets':3,'egressPackets':3 if positive else 0,'witnessCounts':{k:int(positive and k==probe) for k in ('tcp4','tcp6','udp4','udp6')},'responseSHA256':receipt}
    assert v.validate(m,h,p,private)['runtime_authorized'] is False
    for mutate in [lambda x:x.update(osOff=False),lambda x:x.update(probeAttempted=False),lambda x:x['exchanges'][1]['response'].update(state='ready'),lambda x:x['exchanges'][2]['response'].update(id=f.uid()),lambda x:x['exchanges'].append(x['exchanges'][0])]:
        bad=copy.deepcopy(h);mutate(bad)
        with pytest.raises(v.Invalid):v.validate(m,bad,p,private)
    for mutate in [lambda x:x.update(ingressPackets=0),lambda x:x.update(observationClosed=False),lambda x:x.update(runID=f.uid()),lambda x:x.update(peerInputSHA256='f'*64),lambda x:x['witnessCounts'].update(tcp4=2),lambda x:x.update(responseSHA256='0'*64)]:
        bad=copy.deepcopy(p);mutate(bad)
        with pytest.raises(v.Invalid):v.validate(m,h,bad,private)

def test_no_arbitrary_fixtures_or_overwrites(tmp_path):
    for kind,probe,mode,local in [('vlessReality','udp4','positive',None),('amneziaWG1','tcp4','positive',0xc0a80150),('wireGuard','tcp4','wrong-psk',None)]:
        with pytest.raises(ValueError):f.generate(kind,probe,mode,local)
    root=tmp_path/'private';f.write(root,'wireGuard','tcp4','positive',None)
    assert root.stat().st_mode&0o777==0o700 and all(p.stat().st_mode&0o777==0o600 for p in root.iterdir())
    with pytest.raises(FileExistsError):f.write(root,'wireGuard','tcp4','positive',None)


@pytest.mark.parametrize('kind,probe',[('wireGuard','tcp4'),('wireGuard','udp6'),('amneziaWG1','tcp6'),('amneziaWG1','udp4'),('vlessReality','tcp4')])
def test_real_loopback_witness_rejects_wrong_nonce_and_detects_duplicates(kind,probe):
    import socket,threading
    from unified_loopback_witness import LoopbackWitness
    witness=LoopbackWitness(kind,probe,'a'*(48 if kind=='amneziaWG1' else 40))
    family=socket.AF_INET if probe.endswith('4') else socket.AF_INET6
    address='127.0.0.1' if family==socket.AF_INET else '::1'
    ty=socket.SOCK_DGRAM if probe.startswith('udp') else socket.SOCK_STREAM
    with socket.socket(family,ty) as server:
        server.bind((address,0));target=server.getsockname()
        if ty==socket.SOCK_STREAM:server.listen(3)
        thread=threading.Thread(target=witness.serve,args=(server,3));thread.start()
        try:
            for payload,valid in [(witness.request.replace(b'aaaa',b'bbbb'),False),(witness.request,True),(witness.request,True)]:
                with socket.socket(family,ty) as client:
                    client.settimeout(.20 if not valid and ty==socket.SOCK_DGRAM else 1.5);client.connect(target);client.sendall(payload)
                    if ty==socket.SOCK_STREAM:client.shutdown(socket.SHUT_WR)
                    try:
                        reply=client.recv(256)
                        if ty==socket.SOCK_STREAM:
                            while True:
                                more=client.recv(256)
                                if not more:break
                                reply+=more
                    except TimeoutError:reply=b''
                    assert (witness.body in reply)==valid
        finally:thread.join(timeout=3)
        assert not thread.is_alive();o=witness.observation();assert o['matches']==o['responses']==2 and o['runtime_authorized'] is False


def test_staged_review_verifies_exact_private_file_set(tmp_path,monkeypatch):
    import json
    import stage_unified_source_review as s
    root=tmp_path/'review';root.mkdir(mode=0o700)
    original=b'compile receipt fixture';c=root/'candidate-compile-manifest.json';c.write_bytes(original);c.chmod(0o600)
    monkeypatch.setattr(s,'CANDIDATE',f.digest(original))
    notice=root/'NOTICE';notice.write_bytes(b'original notice fixture');notice.chmod(0o600)
    m={'schema':1,'release_authorized':False,'native_candidate_sha256':s.CANDIDATE,'files':{c.name:s.sha(c),notice.name:s.sha(notice)}}
    manifest=root/'manifest.json';manifest.write_text(json.dumps(m));manifest.chmod(0o600)
    assert s.verify_staged_review(root)==m
    notice.write_bytes(b'changed')
    with pytest.raises(ValueError,match='file drift'):s.verify_staged_review(root)
    notice.write_bytes(b'original notice fixture');other=root/'extra';other.symlink_to(notice)
    with pytest.raises(ValueError,match='symlink'):s.verify_staged_review(root)


@pytest.mark.parametrize('mode,log',[('positive','AWG_PEER_READY\nAWG_WITNESS tcp4=1 tcp6=0 udp4=0 udp6=0 sent=8 received=9 rejected=0\n'),('wrong-key','AWG_PEER_READY\nAWG_WITNESS tcp4=0 tcp6=0 udp4=0 udp6=0 sent=0 received=2 rejected=0\n'),('wrong-psk','AWG_PEER_READY\nAWG_WITNESS tcp4=0 tcp6=0 udp4=0 udp6=0 sent=2 received=2 rejected=0\n')])
def test_reference_awg_adapter_requires_closed_exact_peer_observation(mode,log):
    import adapt_unified_awg_peer_receipt as a
    m,private,peer=f.generate('amneziaWG1','tcp4',mode,0xc0a80122)
    w=f.witness_input(m,private)
    result=a.convert(m,private,peer,w,log,0)
    assert result['candidateManifestSHA256']==f.CONTAINING_CANDIDATE
    assert result['observationClosed'] and result['ingressPackets']>0
    for bad in [log+log,log.replace('AWG_PEER_READY',''),log+'unclosed\n',log.replace('received=','received=10000'),log.replace('udp6=0','udp6=1')]:
        with pytest.raises(v.Invalid):a.convert(m,private,peer,w,bad,0)
    with pytest.raises(v.Invalid):a.convert(m,private,peer,w,log,1)
    with pytest.raises(v.Invalid):a.convert(m,private,dict(peer,Nonce='0'*48),w,log,0)
    with pytest.raises(v.Invalid):a.convert(m,private,peer,dict(w,runID=f.uid()),log,0)


def test_containing_host_requires_explicit_arm_and_preserves_production_targets():
    h=(TOOLS/'UnifiedAcceptanceHost/UnifiedAcceptanceApp.swift').read_text()
    assert 'approvedLaunch,armed,quiescence' in h and 'stillAuthorized:{self.generation==token && !self.cancelled}' in h
    assert 'try FileManager.default.removeItem(at:path)' in h and 'withoutOverwriting' in h
    assert 'saveToPreferences' not in h and 'removeFromPreferences' not in h
    assert 'onAppear' not in h and 'onChange(of:phase)' in h
    b=(TOOLS/'build_product_unified_candidate_unsigned.sh').read_text()
    assert 'HOST_REQUIRES_SYNTHETIC_RUNTIME' in b and 'embed: true' in b and "x.pop('APLKeychainAccessGroup',None)" in b
    assert 'no runnable bundle retained' in b
    assert 'UnifiedAcceptanceHost' not in (TOOLS.parent/'project.yml').read_text()
