#!/usr/bin/env python3
"""Fixed AWG test-only split route input. No actual network or device setup."""
import argparse,json,os,pathlib
import unified_synthetic_fixture as base

def target(case,probe):
    if case not in ('included','excluded') or probe not in base.CASES['amneziaWG1']:raise ValueError('invalid split probe')
    return ('2001:db8::' if probe.endswith('6') else '192.0.2.')+('2' if case=='included' else '3')

def generate(case,probe,local,*,no_tproxy=False):
    addr=target(case,probe)
    m,h,p=base.generate('amneziaWG1',probe,'positive',local,candidate=base.NO_TPROXY_SPLIT_CANDIDATE if no_tproxy else base.SPLIT_CANDIDATE)
    w=base.witness_input(m,h)
    m.update(splitCase=case,target=addr,tunnelObserver=base.uid(),externalObserver=base.uid())
    h['splitCase']=case
    w.update(splitCase=case,target=addr,tunnelObserver=m['tunnelObserver'],externalObserver=m['externalObserver'])
    return m,h,p,w

def write(root,case,probe,local,*,no_tproxy=False):
    m,h,p,w=generate(case,probe,local,no_tproxy=no_tproxy);root.mkdir(mode=0o700)
    for name,data in [('manifest.json',m),('host-input.json',h),('peer-input.json',p),('witness-input.json',w)]:
        fd=os.open(root/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'w') as f:json.dump(data,f);f.write('\n')
    return m

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=pathlib.Path);p.add_argument('case',choices=['included','excluded']);p.add_argument('probe',choices=base.CASES['amneziaWG1']);p.add_argument('--local-ipv4',type=int,required=True);p.add_argument('--no-tproxy',action='store_true');a=p.parse_args()
    m=write(a.output,a.case,a.probe,a.local_ipv4,no_tproxy=a.no_tproxy);print('PRIVATE_SPLIT_FIXTURE_CREATED',m['runID'],m['splitCase'],m['probe'])
