#!/usr/bin/env python3
"""Plan and correlate the 30 exact new-candidate cases; never runs a device."""
import json,os,pathlib,re,sys
import unified_synthetic_fixture as f
import unified_split_route_fixture as s
from validate_unified_synthetic_receipt import exact,need,read,uuidstr,validate
from validate_unified_split_route_receipt import validate as validate_split,verify_observation_files
from audit_reference_peer_artifacts import audit

def cases():
    rows=[]
    for kind,probes in f.CASES.items():
        for probe in probes:
            for mode in f.MODES[kind]:
                rows.append({'id':f'{kind}-{probe}-{mode}','kind':kind,'probe':probe,'mode':mode,'splitCase':None,'candidateManifestSHA256':f.NO_TPROXY_CANDIDATE})
    for probe in f.CASES['amneziaWG1']:
        for direction in ('included','excluded'):
            rows.append({'id':f'awg-split-{probe}-{direction}','kind':'amneziaWG1','probe':probe,'mode':'positive','splitCase':direction,'candidateManifestSHA256':f.NO_TPROXY_SPLIT_CANDIDATE})
    assert len(rows)==30 and len({r['id'] for r in rows})==30
    return rows

def correlate_case(case,root,observations,provenance=None):
    m=read(root/'manifest.json');private=read(root/'host-input.json');peer=read(root/'peer-input.json');witness=read(root/'witness-input.json')
    for k in ('kind','probe','mode','candidateManifestSHA256'):need(m[k]==case[k],'case binding mismatch')
    need(m.get('splitCase')==case['splitCase'],'case route mismatch')
    h=read(observations/'host.json')
    if case['splitCase'] is None:
        need(type(provenance)==str and re.fullmatch('[0-9a-f]{64}',provenance),'independent reference provenance required')
        p=audit(root,observations/'peer',provenance)['peerReceipt'];result=validate(m,h,p,private)
        evidence=[provenance]
    else:
        t,e=observations/'tunnel',observations/'external';tr,er=read(t/'receipt.json'),read(e/'receipt.json')
        need(t.resolve()!=e.resolve(),'same observer directory')
        result=validate_split(m,h,private,peer,witness,tr,er);verify_observation_files(t,tr);verify_observation_files(e,er)
        evidence=[o[k] for o in (tr,er) for k in ('captureSHA256','preflightSHA256')]
    return {'id':case['id'],'runID':m['runID'],'owner':m['owner'],'challengeSHA256':m['challengeSHA256'],'evidence':evidence,'status':result['status'],'candidateManifestSHA256':m['candidateManifestSHA256']}

def summarize(records):
    expected={r['id']:r for r in cases()};seen=set();runs=set();owners=set();challenges=set();evidence=set()
    for r in records:
        exact(r,'id runID owner challengeSHA256 evidence status candidateManifestSHA256')
        need(r['id'] in expected and r['id'] not in seen,'duplicate or unknown case');c=expected[r['id']]
        need(r['candidateManifestSHA256']==c['candidateManifestSHA256'],'wrong candidate')
        need(r['status']==('split_route_receipts_correlated_only' if c['splitCase'] else 'correlated_receipt_only'),'not correlated')
        need(uuidstr(r['runID']) and uuidstr(r['owner']) and r['runID'] not in runs|owners and r['owner'] not in runs|owners and r['runID']!=r['owner'],'reused run or owner')
        need(type(r['challengeSHA256'])==str and re.fullmatch('[0-9a-f]{64}',r['challengeSHA256']) and r['challengeSHA256'] not in challenges,'reused challenge')
        v=r['evidence'];need(type(v)==list and len(v)==(4 if c['splitCase'] else 1) and all(type(x)==str and re.fullmatch('[0-9a-f]{64}',x) for x in v) and len(set(v))==len(v) and not evidence.intersection(v),'reused evidence')
        seen.add(r['id']);runs.add(r['runID']);owners.add(r['owner']);challenges.add(r['challengeSHA256']);evidence.update(v)
    return {'correlated':len(seen),'planned':30,'missing':sorted(set(expected)-seen),'scope':'structural correlation only; signed identity and independent physical review required','runtime_authorized':False,'release_authorized':False}

def check_directory(root):
    need(root.is_dir() and not root.is_symlink() and root.stat().st_mode&0o077==0,'unsafe matrix directory')
    known={r['id']:r for r in cases()};records=[]
    for item in sorted(root.iterdir()):
        need(item.name in known and item.is_dir() and not item.is_symlink() and item.stat().st_mode&0o077==0,'unknown case directory')
        meta=read(item/'review.json');exact(meta,'peerProvenanceSHA256');records.append(correlate_case(known[item.name],item/'fixture',item/'observations',meta['peerProvenanceSHA256']))
    return summarize(records)

if __name__=='__main__':
    if sys.argv[1:]==['--plan']:print(json.dumps({'cases':cases(),'status':'not executed','runtime_authorized':False,'release_authorized':False},indent=2))
    elif len(sys.argv)==3 and sys.argv[1]=='--verify':print(json.dumps(check_directory(pathlib.Path(sys.argv[2])),indent=2))
    else:raise SystemExit('usage: unified_acceptance_matrix.py --plan | --verify PRIVATE_CASE_ROOT')
