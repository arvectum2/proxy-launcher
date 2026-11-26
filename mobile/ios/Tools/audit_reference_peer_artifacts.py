#!/usr/bin/env python3
"""Offline audit of actual reference-peer logs against independently supplied metadata.
No capture, launch, signing or network operations. Digest checks bind files but
cannot establish that the trusted operator selected the correct machine/process.
"""
import hashlib,json,os,pathlib,re,stat,sys
from validate_unified_synthetic_receipt import exact,need,read
from unified_synthetic_fixture import json_digest,witness_input
import adapt_unified_awg_peer_receipt as awg
import adapt_unified_wg_peer_receipt as wg
import adapt_unified_vless_peer_receipt as vless

def private_bytes(path,limit):
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    with os.fdopen(fd,'rb') as f:
        st=os.fstat(f.fileno());need(stat.S_ISREG(st.st_mode) and st.st_mode&0o077==0 and 0<st.st_size<=limit,'unsafe artifact')
        data=f.read(limit+1);need(len(data)==st.st_size,'artifact changed during read');return data

def sha(data):return hashlib.sha256(data).hexdigest()

def audit(root,observation,expected_digest):
    for r in (root,observation):need(r.is_dir() and not r.is_symlink() and r.stat().st_mode&0o077==0,'unsafe directory')
    need(root.resolve()!=observation.resolve(),'independent observation directory required')
    raw=private_bytes(observation/'provenance.json',16384)
    need(sha(raw)==expected_digest,'independent provenance record mismatch')
    provenance=read(observation/'provenance.json');need(json.loads(raw)==provenance,'provenance changed')
    exact(provenance,'schema runID candidateManifestSHA256 peerInputSHA256 challengeSHA256 kind probe mode scope peerBinarySHA256 processExit logSHA256')
    need(type(provenance['schema'])==int and provenance['schema']==1 and provenance['scope']=='independent_reference_peer','wrong observation scope')
    m=read(root/'manifest.json');private=read(root/'host-input.json');peer=read(root/'peer-input.json');witness=read(root/'witness-input.json')
    for key in ('runID','candidateManifestSHA256','peerInputSHA256','challengeSHA256','kind','probe','mode'):need(provenance[key]==m[key],'cross-run provenance')
    need('splitCase' not in m and json_digest(peer)==m['peerInputSHA256'] and witness==witness_input(m,private),'fixture mismatch')
    need(type(provenance['processExit'])==int and provenance['processExit']==0,'peer did not exit cleanly')
    for key in ('peerBinarySHA256','logSHA256'):need(type(provenance[key])==str and re.fullmatch('[a-f0-9]{64}',provenance[key]),'bad artifact digest')
    log=private_bytes(observation/'capture.raw',65536);need(sha(log)==provenance['logSHA256'],'peer log hash mismatch')
    if m['kind']=='wireGuard':r=wg.convert(m,private,peer,witness,log.decode(),provenance['processExit'])
    elif m['kind']=='amneziaWG1':r=awg.convert(m,private,peer,witness,log.decode(),provenance['processExit'])
    elif m['kind']=='vlessReality':
        # Byte-counter observation produced by independently trusted TCP
        # observer; do not claim parsing of encrypted stream/packet capture.
        obs=read(observation/'capture.raw');need(json.loads(log)==obs,'observation changed')
        r=vless.convert(m,private,peer,witness,obs)
    else:raise ValueError('unknown protocol')
    return {'status':'reference_artifacts_correlated_only','peerReceipt':r,'provenanceSHA256':expected_digest,'peerBinarySHA256':provenance['peerBinarySHA256'],'runtime_authorized':False,'release_authorized':False}

if __name__=='__main__':
    if len(sys.argv)!=4:raise SystemExit('usage: audit_reference_peer_artifacts.py PRIVATE_FIXTURE_DIR SEPARATE_OBSERVATION_DIR INDEPENDENT_METADATA_SHA256')
    print(json.dumps(audit(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]),sys.argv[3]),sort_keys=True))
