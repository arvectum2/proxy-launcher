#!/usr/bin/env python3
"""Compare exact pinned source graphs; reuse only original covered notices."""
import hashlib,json,pathlib,re,subprocess,sys

UNIFIED='57b279f366b47fd27a46b201088a997fb03f68205f5189dc2931ae43f00011e6'
OLD_GRAPH='b2dc2d8f6628d581ff29ba2737e654079a79363f9f2c0beeb11510a7e84eaa21'
XRAY='bafc1906d5bf07c462e01f5f958e1ae495a476f20a54d88ae36b4da93e1e1d66'
AWG='8c29add5efe9035f12c288ca99489e3ce4f1323cd8f85c6a63c353f812f9fac4'
AWG_MODULE='github.com/amnezia-vpn/amneziawg-go/v3'
AWG_COMMIT='b5928efb6ca19f0153958460c3d141f04abc5c2e'

def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def pinned(p,digest):
    if sha(p)!=digest:raise ValueError('evidence hash mismatch: '+p.name)
    return json.loads(p.read_text())

def graph(p):
    raw=p.read_text();d=json.JSONDecoder();i=0;rows={}
    while i<len(raw):
        while i<len(raw) and raw[i].isspace():i+=1
        if i==len(raw):break
        v,i=d.raw_decode(raw,i);key=v['ImportPath']
        if key in rows or v.get('Error') or v.get('DepsErrors'):raise ValueError('invalid graph')
        rows[key]=v
    return rows

def version(p):
    m=p.get('Module',{})
    return m.get('Path'),m.get('Version','main') if m else None

def compare(old,new):
    if set(old)-set(new):raise ValueError('removed packages require review')
    for k in old:
        if version(old[k])!=version(new[k]) or new[k].get('Module',{}).get('Replace'):raise ValueError('changed package: '+k)
    extra=set(new)-set(old)
    if not extra or any(version(new[k])!=(AWG_MODULE,'v3.1.20260828') for k in extra):raise ValueError('unreviewed additional package')
    return sorted(extra)

def audit(base):
    u=base/'product-unified-go-link-evidence-20261115';x=base/'xray-source-20261115';a=base/'awg-ios-source-license-inventory-20261115';source=base/'awg-source-20261114/awg'
    receipt=pinned(u/'manifest.json',UNIFIED)
    if receipt['release_authorized'] or receipt['awg_commit']!=AWG_COMMIT:raise ValueError('unexpected receipt')
    for name,d in receipt['files'].items():
        if pathlib.Path(name).name!=name or sha(u/name)!=d:raise ValueError('unified receipt file mismatch')
    original=x/'source-build/ios-deps.json'
    if sha(original)!=OLD_GRAPH:raise ValueError('original graph drift')
    old,new=graph(original),graph(u/'ios-deps.json');extra=compare(old,new)
    def git(*args):return subprocess.check_output(['git','-C',str(source),*args])
    if git('rev-parse','HEAD').decode().strip()!=AWG_COMMIT or git('status','--porcelain'):raise ValueError('AWG source drift')
    roots=set()
    for k in extra:
        package=new[k];mod=package['Module'];directory=pathlib.Path(package['Dir']).resolve()
        if not directory.is_relative_to(source.resolve()) or pathlib.Path(mod['Replace']['Dir']).resolve()!=source.resolve():raise ValueError('AWG package outside pinned checkout')
        while directory!=source.resolve():roots.add(directory.relative_to(source.resolve()).as_posix());directory=directory.parent
    xi=pinned(x/'ios-license-inventory-nested/manifest.json',XRAY);ai=pinned(a/'manifest.json',AWG)
    if xi['graph_sha256']!=OLD_GRAPH:raise ValueError('notice graph mismatch')
    files=0
    for row in xi['modules']:
        for f in row['files']:
            if sha(x/'ios-license-inventory-nested'/f['file'])!=f['sha256']:raise ValueError('original notice drift')
            files+=1
    awg=next(row for row in ai['components'] if row['module']==AWG_MODULE and row['version']=='v3.1.20260828')
    all_awg_notices=[]
    for name in git('ls-tree','-r','--name-only',AWG_COMMIT).decode().splitlines():
        p=pathlib.PurePosixPath(name)
        if str(p.parent) in roots|{'.'} and re.match(r'^(licen[cs]e|copying|notice|patents|copyright|authors)(?:$|[-_.])',p.name,re.I):all_awg_notices.append(name)
    if all_awg_notices!=['LICENSE']:raise ValueError('additional AWG notices require review')
    notice=awg['files'];
    if len(notice)!=1 or sha(a/notice[0]['path'])!=notice[0]['sha256'] or hashlib.sha256(git('show',AWG_COMMIT+':LICENSE')).hexdigest()!=notice[0]['sha256']:raise ValueError('AWG original license drift')
    return {'release_authorized':False,'scope':'source graph notice coverage delta only; not final linked SBOM or legal clearance','original_packages':len(old),'unified_packages':len(new),'added_packages':extra,'unchanged_xray_and_go_components':len(xi['modules']),'original_xray_notice_files':files,'additional_awg_notice_files':1,'unified_receipt_sha256':UNIFIED,'remaining':['combined artifact/source delivery and legal review','actual selected Rust and SDK closure','original tproxy-config notice','runtime acceptance']}

if __name__=='__main__':
    print(json.dumps(audit(pathlib.Path(sys.argv[1]).resolve()),indent=2,sort_keys=True))
