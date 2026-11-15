#!/usr/bin/env python3
"""Validate independent VLESS observation; TCP byte counts are not packet counts."""
import json,pathlib,re,sys
from unified_synthetic_fixture import CANDIDATES,digest,json_digest,witness_input
from validate_unified_synthetic_receipt import read,need,exact

def convert(m,private,peer,witness,observation):
    need(m.get('kind')=='vlessReality' and m.get('candidateManifestSHA256') in CANDIDATES and m.get('runtime_authorized') is False and m.get('probe')=='tcp4','wrong VLESS fixture')
    need(witness==witness_input(m,private) and json_digest(peer)==m['peerInputSHA256'],'input mismatch')
    nonce=witness['nonce'];need(type(nonce)==str and re.fullmatch('[0-9a-f]{40}',nonce) and digest(nonce.encode())==m['challengeSHA256'],'challenge mismatch')
    exact(observation,'runID candidateManifestSHA256 peerInputSHA256 challengeSHA256 ready stopped processExit observationClosed ingressBytes egressBytes witnessCount responseSHA256')
    for k in ('runID','candidateManifestSHA256','peerInputSHA256','challengeSHA256'):need(observation[k]==m[k],'observation binding mismatch')
    need(observation['ready'] is True and observation['stopped'] is True and type(observation['processExit'])==int and observation['processExit']==0 and observation['observationClosed'] is True,'incomplete observation')
    for k in ('ingressBytes','egressBytes'):need(type(observation[k])==int and 0<=observation[k]<=1048576,'invalid stream counters')
    positive=m['mode']=='positive';need(m['mode'] in ('positive','wrong-key'),'invalid mode')
    expected=digest(('APL_RECEIPT:'+nonce).encode()) if positive else None
    need(observation['ingressBytes']>0 and (not positive or observation['egressBytes']>0) and type(observation['witnessCount'])==int and observation['witnessCount']==int(positive) and observation['responseSHA256']==expected,'independent VLESS witness failure')
    return {**{k:m[k] for k in ('runID','candidateManifestSHA256','challengeSHA256','peerInputSHA256','probe','mode')},'schema':2,'observationClosed':True,'ingressBytes':observation['ingressBytes'],'egressBytes':observation['egressBytes'],'witnessCounts':{'tcp4':int(positive),'tcp6':0,'udp4':0,'udp6':0},'responseSHA256':expected}

if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('usage: adapt_unified_vless_peer_receipt.py PRIVATE_FIXTURE_DIR INDEPENDENT_OBSERVATION')
    r=pathlib.Path(sys.argv[1]);print(json.dumps(convert(read(r/'manifest.json'),read(r/'host-input.json'),read(r/'peer-input.json'),read(r/'witness-input.json'),read(pathlib.Path(sys.argv[2]))),sort_keys=True))
