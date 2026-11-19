#!/usr/bin/env python3
"""Offline correlation of joined reference WG terminal counters, not host claims."""
import json,pathlib,re,sys
from unified_synthetic_fixture import CANDIDATES,digest,json_digest,witness_input
from validate_unified_synthetic_receipt import need,read

PATTERN=re.compile(r'WG_WITNESS tcp4=(\d{1,4}) tcp6=(\d{1,4}) udp4=(\d{1,4}) udp6=(\d{1,4}) sent=(\d{1,4}) received=(\d{1,4})')

def parse_terminal(log,code):
    need(type(code)==int and code==0 and type(log)==str and len(log)<=65536,'peer failed')
    lines=log.splitlines();ready=[i for i,s in enumerate(lines) if s=='PEER_QA_READY_server'];stopped=[i for i,s in enumerate(lines) if s=='PEER_QA_STOPPED_server'];counts=[i for i,s in enumerate(lines) if s.startswith('WG_WITNESS')]
    need(len(ready)==len(stopped)==len(counts)==1 and ready[0]<counts[0] and counts[0]+1==stopped[0]==len(lines)-1,'missing or duplicate terminal record')
    m=PATTERN.fullmatch(lines[counts[0]]);need(m is not None,'invalid counters');v=tuple(map(int,m.groups()));need(all(n<=4096 for n in v),'counter limit');return v

def convert(m,private,peer,witness,log,code):
    need(m.get('kind')=='wireGuard' and m.get('candidateManifestSHA256') in CANDIDATES and m.get('runtime_authorized') is False,'wrong case')
    need(witness==witness_input(m,private) and json_digest(peer)==m['peerInputSHA256'],'input mismatch')
    nonce=witness['nonce'];need(isinstance(nonce,str) and re.fullmatch('[0-9a-f]{40}',nonce) and peer.get('nonce')==nonce and digest(nonce.encode())==m['challengeSHA256'],'challenge mismatch')
    a,b,c,d,sent,received=parse_terminal(log,code);counts=dict(zip(('tcp4','tcp6','udp4','udp6'),(a,b,c,d)))
    mode=m['mode'];probe=m['probe'];need(mode in ('positive','wrong-key') and probe in counts,'wrong case')
    positive=mode=='positive';need(counts=={k:int(positive and k==probe) for k in counts} and received>0 and (not positive or sent>0),'independent witness failure')
    return {**{k:m[k] for k in ('runID','candidateManifestSHA256','challengeSHA256','peerInputSHA256','probe','mode')},'schema':1,'observationClosed':True,'ingressPackets':received,'egressPackets':sent,'witnessCounts':counts,'responseSHA256':digest(('APL_RECEIPT:'+nonce).encode()) if positive else None}

if __name__=='__main__':
    if len(sys.argv)!=4:raise SystemExit('usage: adapt_unified_wg_peer_receipt.py PRIVATE_FIXTURE_DIR PEER_LOG EXIT_CODE')
    root=pathlib.Path(sys.argv[1]);log=pathlib.Path(sys.argv[2]);need(not log.is_symlink() and log.is_file() and log.stat().st_size<=65536,'unsafe log')
    print(json.dumps(convert(read(root/'manifest.json'),read(root/'host-input.json'),read(root/'peer-input.json'),read(root/'witness-input.json'),log.read_text(),int(sys.argv[3])),sort_keys=True))
