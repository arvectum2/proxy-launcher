#!/usr/bin/env python3
"""Convert independent reference peer terminal counters, not host claims.
Offline adapter only. A trusted operator must verify process/binary/config
provenance and observation window, including preflight for negative cases.
"""
import json,pathlib,re,sys
from unified_synthetic_fixture import CANDIDATES,digest,json_digest,witness_input
from validate_unified_synthetic_receipt import read,need

PATTERN=re.compile(r'AWG_WITNESS tcp4=(\d{1,4}) tcp6=(\d{1,4}) udp4=(\d{1,4}) udp6=(\d{1,4}) sent=(\d{1,4}) received=(\d{1,4}) rejected=(\d{1,4})')

def parse_terminal(log,exit_code):
    need(type(exit_code)==int and exit_code==0 and type(log)==str and len(log)<=65536,'peer process failed or log oversized')
    lines=log.splitlines();ready=[i for i,s in enumerate(lines) if s=='AWG_PEER_READY'];end=[i for i,s in enumerate(lines) if s.startswith('AWG_WITNESS')]
    need(len(ready)==len(end)==1 and ready[0]<end[0],'missing or duplicate terminal observation')
    match=PATTERN.fullmatch(lines[end[0]]);need(match is not None and not any(s.strip() for s in lines[end[0]+1:]),'invalid terminal record')
    values=tuple(map(int,match.groups()));need(all(0<=n<=4096 for n in values),'counter limit')
    return values

def convert(m,private,peer,witness,log,exit_code):
    need(m.get('kind')=='amneziaWG1' and m.get('candidateManifestSHA256') in CANDIDATES and m.get('runtime_authorized') is False,'wrong candidate or protocol')
    need(witness==witness_input(m,private) and json_digest(peer)==m['peerInputSHA256'],'peer/witness binding mismatch')
    nonce=witness['nonce'];need(type(nonce)==str and re.fullmatch('[0-9a-f]{48}',nonce) and peer.get('Nonce')==nonce and digest(nonce.encode())==m['challengeSHA256'],'challenge mismatch')
    tcp4,tcp6,udp4,udp6,sent,received,rejected=parse_terminal(log,exit_code)
    counts=dict(zip(('tcp4','tcp6','udp4','udp6'),(tcp4,tcp6,udp4,udp6)))
    mode=m['mode'];probe=m['probe'];need(mode in ('positive','wrong-key','wrong-psk') and probe in counts,'invalid case')
    positive=mode=='positive';need(counts=={k:int(positive and k==probe) for k in counts} and received>0 and (not positive or sent>0),'independent witness failure')
    # Reference peer increments a count only after an exact nonce match and
    # successful write of APL:<nonce>. Digest is derived from that observed
    # invariant, not independently captured response bytes.
    return {**{k:m[k] for k in ('runID','candidateManifestSHA256','challengeSHA256','peerInputSHA256','probe','mode')},'schema':1,'observationClosed':True,'ingressPackets':received,'egressPackets':sent,'witnessCounts':counts,'responseSHA256':digest(('APL:'+nonce).encode()) if positive else None}

if __name__=='__main__':
    if len(sys.argv)!=4:raise SystemExit('usage: adapt_unified_awg_peer_receipt.py PRIVATE_FIXTURE_DIR CAPTURED_PEER_LOG PROCESS_EXIT_CODE')
    root=pathlib.Path(sys.argv[1]);log=pathlib.Path(sys.argv[2]);need(not log.is_symlink() and log.is_file() and log.stat().st_size<=65536,'unsafe log')
    print(json.dumps(convert(read(root/'manifest.json'),read(root/'host-input.json'),read(root/'peer-input.json'),read(root/'witness-input.json'),log.read_text(),int(sys.argv[3])),sort_keys=True))
