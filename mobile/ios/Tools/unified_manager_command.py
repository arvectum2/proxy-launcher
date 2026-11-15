#!/usr/bin/env python3
"""Create a private future QA command and check matching read-back receipt. No device I/O."""
import json,os,pathlib,sys
from unified_synthetic_fixture import CONTAINING_CANDIDATE,SPLIT_CANDIDATE,uid
from validate_unified_synthetic_receipt import exact,need,read,uuidstr

def command(manifest,action):
    need(manifest.get('candidateManifestSHA256') in (CONTAINING_CANDIDATE,SPLIT_CANDIDATE) and manifest.get('runtime_authorized') is False and uuidstr(manifest.get('owner')),'wrong current compile candidate')
    need(action in ('prepare','remove'),'invalid action')
    return {'schema':1,'requestID':uid(),'owner':manifest['owner'],'action':action}

def verify(manifest,c,r):
    exact(c,'schema requestID owner action');exact(r,'schema requestID owner action matched allVisibleOff')
    need(manifest.get('candidateManifestSHA256') in (CONTAINING_CANDIDATE,SPLIT_CANDIDATE) and manifest.get('runtime_authorized') is False,'wrong compile candidate')
    need(type(c['schema'])==type(r['schema'])==int and c['schema']==r['schema']==1 and uuidstr(c['requestID']) and uuidstr(c['owner']) and c['owner']==manifest.get('owner') and c['requestID']!=c['owner'],'wrong command')
    need(c['action'] in ('prepare','remove') and all(r[k]==c[k] for k in ('requestID','owner','action')),'wrong command receipt')
    need(type(r['matched'])==int and r['matched']==int(c['action']=='prepare') and r['allVisibleOff'] is True,'manager readback missing')
    return {'status':'manager_readback_correlated_only','runtime_authorized':False,'release_authorized':False,'requestID':c['requestID'],'action':c['action']}

if __name__=='__main__':
    if len(sys.argv)!=5:raise SystemExit('usage: unified_manager_command.py create MANIFEST prepare|remove NEW_COMMAND | verify MANIFEST COMMAND RECEIPT')
    op,manifest,a,b=sys.argv[1:];m=read(pathlib.Path(manifest))
    if op=='create':
        c=command(m,a);fd=os.open(b,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
        with os.fdopen(fd,'w') as f:json.dump(c,f);f.write('\n')
        print('PRIVATE_MANAGER_COMMAND_CREATED',c['action'],c['requestID'])
    elif op=='verify':print(json.dumps(verify(m,read(pathlib.Path(a)),read(pathlib.Path(b))),sort_keys=True))
    else:raise SystemExit('unsupported operation')
