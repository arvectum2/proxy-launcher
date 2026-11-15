#!/usr/bin/env python3
"""Correlate trusted independent QA records; never authorize execution or release."""
import base64,json,pathlib,re,stat,sys,uuid
from unified_synthetic_fixture import CASES,MODES,CANDIDATES,digest,json_digest,witness_input
class Invalid(ValueError):pass

def need(condition,reason):
    if not condition:raise Invalid(reason)

def exact(value,keys):
    need(type(value)==dict and set(value)==set(keys.split()),'invalid schema')

def uuidstr(x):
    try:return type(x)==str and str(uuid.UUID(x)).upper()==x
    except (ValueError,TypeError,AttributeError):return False

def identity(x,provider):
    exact(x,'epoch generation provider');need(uuidstr(x['epoch']) and type(x['generation'])==int and x['generation']==1 and x['provider']==provider,'identity mismatch')

def validate(m,h,p,private):
    exact(m,'schema runID owner identity kind probe mode candidateManifestSHA256 challengeSHA256 fixtureSHA256 peerInputSHA256 runtime_authorized')
    exact(private,'runID owner identity kind probe mode nonce fixture localIPv4')
    need(type(m['schema'])==int and m['schema']==1 and m['runtime_authorized'] is False and m['candidateManifestSHA256'] in CANDIDATES,'candidate mismatch')
    kind,probe,mode=m['kind'],m['probe'],m['mode'];need(kind in CASES and probe in CASES[kind] and mode in MODES[kind],'unsupported case')
    need(uuidstr(m['runID']) and uuidstr(m['owner']),'invalid test ID')
    provider='standalone-awg' if kind=='amneziaWG1' else 'rust-xray';identity(m['identity'],provider)
    for k in ('runID','owner','identity','kind','probe','mode'):need(private[k]==m[k],'private fixture mismatch')
    nonce=private['nonce'];need(type(nonce)==str and re.fullmatch('[0-9a-f]{%s}'%(48 if kind=='amneziaWG1' else 40),nonce),'invalid challenge')
    need(digest(nonce.encode())==m['challengeSHA256'] and type(m['peerInputSHA256'])==str and re.fullmatch('[0-9a-f]{64}',m['peerInputSHA256']),'challenge/peer input mismatch')
    fixture=base64.b64decode(private['fixture'],validate=True);need(digest(fixture)==m['fixtureSHA256'] and (len(fixture)==96 if kind=='amneziaWG1' else 0<len(fixture)<=4096),'fixture mismatch')
    h=dict(h);h.setdefault('responseSHA256',None)
    exact(h,'schema runID owner identity fixtureSHA256 probe mode exchanges responseSHA256 probeAttempted osOff')
    need(type(h['schema'])==int and h['schema']==1 and h['probeAttempted'] is True and h['osOff'] is True,'host completion absent')
    for k in ('runID','owner','identity','fixtureSHA256','probe','mode'):need(h[k]==m[k],'host binding mismatch')
    exchanges=h['exchanges'];need(type(exchanges)==list and len(exchanges)==3,'incomplete or duplicate control transcript')
    seen=set()
    for e,(action,state,stale) in zip(exchanges,[('observe','starting',False),('observe','rejected',True),('drain','drained',False)]):
        exact(e,'request response');q,r=e['request'],e['response'];exact(q,'version id identity action');exact(r,'version id identity action state')
        need(type(q['version'])==type(r['version'])==int and q['version']==r['version']==1 and uuidstr(q['id']) and q['id'] not in seen,'replayed request');seen.add(q['id'])
        identity(q['identity'],provider);need((q['identity']['epoch']!=m['identity']['epoch']) if stale else (q['identity']==m['identity']),'wrong control epoch')
        identity(r['identity'],provider);need(q['action']==action and r==dict(q,state=state),'response mismatch')
    expected=digest((('APL:' if kind=='amneziaWG1' else 'APL_RECEIPT:')+nonce).encode())
    positive=mode=='positive';need(h['responseSHA256']==(expected if positive else None),'host response mismatch')
    exact(p,'schema runID candidateManifestSHA256 challengeSHA256 peerInputSHA256 probe mode observationClosed ingressPackets egressPackets witnessCounts responseSHA256')
    need(type(p['schema'])==int and p['schema']==1 and p['observationClosed'] is True,'peer observation incomplete')
    for k in ('runID','candidateManifestSHA256','challengeSHA256','peerInputSHA256','probe','mode'):need(p[k]==m[k],'peer binding mismatch')
    for k in ('ingressPackets','egressPackets'):need(type(p[k])==int and 0<=p[k]<=4096,'invalid transport counters')
    need(p['ingressPackets']>0 and (not positive or p['egressPackets']>0),'missing independent packet observation')
    counts=p['witnessCounts'];exact(counts,'tcp4 tcp6 udp4 udp6');need(all(type(v)==int for v in counts.values()) and counts=={k:int(positive and k==probe) for k in counts},'unexpected witness count or family')
    need(p['responseSHA256']==(expected if positive else None),'peer response mismatch')
    return {'status':'correlated_receipt_only','runtime_authorized':False,'release_authorized':False,'runID':m['runID'],'kind':kind,'probe':probe,'mode':mode,'scope':'requires independent provenance and actual signed binary identity review; no ready claim'}

def read(path):
    need(not path.is_symlink() and path.is_file() and stat.S_IMODE(path.stat().st_mode)&0o077==0 and 0<path.stat().st_size<=16384,'unsafe receipt file')
    def unique(pairs):
        result={}
        for k,v in pairs:need(k not in result,'duplicate JSON key');result[k]=v
        return result
    return json.loads(path.read_text(),object_pairs_hook=unique)

if __name__=='__main__':
    if len(sys.argv)!=4:raise SystemExit('usage: validate_unified_synthetic_receipt.py PRIVATE_FIXTURE_DIR HOST_RECEIPT PEER_RECEIPT')
    root=pathlib.Path(sys.argv[1]);need(not root.is_symlink() and root.is_dir() and stat.S_IMODE(root.stat().st_mode)&0o077==0,'unsafe fixture dir')
    m=read(root/'manifest.json');private=read(root/'host-input.json')
    need(json_digest(read(root/'peer-input.json'))==m['peerInputSHA256'],'peer input file mismatch')
    need(read(root/'witness-input.json')==witness_input(m,private),'witness input file mismatch')
    print(json.dumps(validate(m,read(pathlib.Path(sys.argv[2])),read(pathlib.Path(sys.argv[3])),private),sort_keys=True))
