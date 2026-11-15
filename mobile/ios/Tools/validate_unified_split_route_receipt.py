#!/usr/bin/env python3
"""Correlate two separately trusted observers; never infer route from silence.
Capture digest fields require independent trusted capture and signed-device
review. This is not a capture tool or an authentication mechanism for JSON.
"""
import hashlib,json,pathlib,re,sys,stat
import unified_synthetic_fixture as base
from unified_split_route_fixture import target
from validate_unified_synthetic_receipt import need,exact,read,uuidstr,validate_host

EXTRA=('splitCase','target','tunnelObserver','externalObserver')
def validate(m,h,private,peer,witness,tunnel,external):
    need(m.get('candidateManifestSHA256')==base.SPLIT_CANDIDATE and m.get('kind')=='amneziaWG1' and m.get('mode')=='positive','wrong route candidate')
    case=m['splitCase'];probe=m['probe'];addr=target(case,probe)
    need(m['target']==addr and private.get('splitCase')==h.get('splitCase')==case,'split target mismatch')
    need(uuidstr(m['tunnelObserver']) and uuidstr(m['externalObserver']) and len({m['tunnelObserver'],m['externalObserver'],m['runID'],m['owner']})==4,'observer identity collision')
    standard={k:v for k,v in m.items() if k not in EXTRA};host=dict(h);host.pop('splitCase');inp=dict(private);inp.pop('splitCase')
    expected=validate_host(standard,host,inp)
    need(base.json_digest(peer)==standard['peerInputSHA256'] and witness==dict(base.witness_input(standard,inp),**{k:m[k] for k in EXTRA}),'wrong fixture inputs')
    # Capture must cover the same test window and contain raw-observation
    # provenance, including the independent preflight of both paths.
    captures=[]
    for role,record in [('tunnel',tunnel),('external',external)]:
        exact(record,'schema runID candidateManifestSHA256 challengeSHA256 peerInputSHA256 splitCase target probe observerID path observationClosed preflightSHA256 captureSHA256 witnessCount responseSHA256')
        need(type(record['schema'])==int and record['schema']==1 and record['observationClosed'] is True and record['path']==role and record['observerID']==m[role+'Observer'],'wrong observer or window')
        for k in ('runID','candidateManifestSHA256','challengeSHA256','peerInputSHA256','splitCase','target','probe'):need(record[k]==m[k],'observer binding mismatch')
        for k in ('preflightSHA256','captureSHA256'):need(type(record[k])==str and re.fullmatch('[a-f0-9]{64}',record[k]),'missing capture digest')
        captures.extend([record['preflightSHA256'],record['captureSHA256']])
        outcome=(case=='included')==(role=='tunnel')
        need(type(record['witnessCount'])==int and record['witnessCount']==int(outcome) and record['responseSHA256']==(expected if outcome else None),'wrong path or missing positive witness')
    need(len(set(captures))==4,'reused capture or preflight')
    return {'status':'split_route_receipts_correlated_only','runID':m['runID'],'splitCase':case,'probe':probe,'runtime_authorized':False,'release_authorized':False,'scope':'requires independent signed binary, preflight and raw capture provenance review'}

def verify_observation_files(root,record):
    need(root.is_dir() and not root.is_symlink() and stat.S_IMODE(root.stat().st_mode)&0o077==0,'unsafe observation directory')
    for name,key in [('preflight.raw','preflightSHA256'),('capture.raw','captureSHA256')]:
        path=root/name
        need(path.is_file() and not path.is_symlink(),'missing observation artifact')
        with path.open('rb') as f:
            import os
            st=os.fstat(f.fileno())
            need(stat.S_ISREG(st.st_mode) and stat.S_IMODE(st.st_mode)&0o077==0 and 0<st.st_size<=128*1024*1024,'unsafe observation artifact')
            need(hashlib.file_digest(f,'sha256').hexdigest()==record[key],'capture hash mismatch')

if __name__=='__main__':
    if len(sys.argv)!=5:raise SystemExit('usage: validate_unified_split_route_receipt.py PRIVATE_FIXTURE_DIR HOST TUNNEL_OBSERVATION_DIR EXTERNAL_OBSERVATION_DIR')
    r=pathlib.Path(sys.argv[1]);need(r.is_dir() and not r.is_symlink() and stat.S_IMODE(r.stat().st_mode)&0o077==0,'unsafe fixture directory')
    t,e=map(pathlib.Path,sys.argv[3:]);need(t.resolve()!=e.resolve(),'observer directories must be separate')
    tr,er=read(t/'receipt.json'),read(e/'receipt.json')
    result=validate(read(r/'manifest.json'),read(pathlib.Path(sys.argv[2])),read(r/'host-input.json'),read(r/'peer-input.json'),read(r/'witness-input.json'),tr,er)
    verify_observation_files(t,tr);verify_observation_files(e,er)
    print(json.dumps(result,sort_keys=True))
