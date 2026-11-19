#!/usr/bin/env python3
"""Private candidate-bound source/notice review; never authorizes distribution."""
import hashlib,json,os,pathlib,stat,sys,tempfile,zipfile,subprocess
from audit_native_candidate_evidence import verify
from stage_unified_source_review import verify_staged_review,put,copy_verified,sha
from audit_unified_go_notices import audit as audit_go,UNIFIED
from verify_ios_no_tproxy_receipt import RECEIPT,ARCHIVE
from unified_synthetic_fixture import NO_TPROXY_CANDIDATE,NO_TPROXY_SPLIT_CANDIDATE
from prepare_ios_rust_without_tproxy import prepare
ROOT=pathlib.Path(__file__).resolve().parents[1]
OLD='60ae765c28b900045d7987703beebdfc6fed3f83e63210a9ba2b7f0549a325fc'
CANDIDATES={'standard':('product-unified-no-tproxy-evidence-20261115',NO_TPROXY_CANDIDATE),'split':('product-unified-no-tproxy-split-evidence-20261115',NO_TPROXY_SPLIT_CANDIDATE)}

def archive_tree(src,dst):
    with zipfile.ZipFile(dst,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for p in sorted(src.rglob('*')):
            name=p.relative_to(src).as_posix()
            if p.is_symlink():
                if name!='.dockerignore' or os.readlink(p)!='.gitignore':raise ValueError('unexpected symlink')
                z.writestr(name,(src/'.gitignore').read_bytes());continue
            if p.is_dir():continue
            if not p.is_file() or name.split('/')[0] in ('target','.git'):raise ValueError('unexpected prepared file')
            z.write(p,name)

def verify_review(p):
    if p.is_symlink() or not p.is_dir() or p.stat().st_mode&0o077:raise ValueError('not private review')
    manifest=p/'manifest.json'
    if manifest.is_symlink() or not manifest.is_file() or manifest.stat().st_mode&0o077:raise ValueError('unsafe manifest')
    m=json.loads(manifest.read_text());assert m['schema']==1 and m['release_authorized'] is False and m['runtime_authorized'] is False
    seen=set()
    for f in p.rglob('*'):
        if f.is_symlink() or f.stat().st_mode&0o077:raise ValueError('unsafe entry')
        if f.is_file() and f!=p/'manifest.json':
            rel=f.relative_to(p).as_posix();seen.add(rel);verify(p,rel,m['files'][rel])
            if f.suffix=='.zip':
                with zipfile.ZipFile(f) as z:
                    names=set()
                    for x in z.infolist():
                        q=pathlib.PurePosixPath(x.filename)
                        if q.is_absolute() or '..' in q.parts or '\\' in x.filename or x.filename in names or stat.S_ISLNK(x.external_attr>>16):raise ValueError('unsafe archive')
                        names.add(x.filename)
                    if z.testzip() is not None:raise ValueError('archive CRC')
    if seen!=set(m['files']):raise ValueError('missing file')
    for label,(_,digest) in CANDIDATES.items():verify(p,'candidates/'+label+'.json',digest)
    verify(p,'rust/research-manifest.json',RECEIPT);verify(p,'go/unified-manifest.json',UNIFIED)
    return m

def stage(base,out):
    if out.exists() or out.is_symlink():raise ValueError('output exists')
    os.umask(0o077)
    old=base/'private-unified-source-review-v2-20261115';verify(old,'manifest.json',OLD);previous=verify_staged_review(old)
    go=audit_go(base);u=base/'product-unified-go-link-evidence-20261115';gm=json.loads(verify(u,'manifest.json',UNIFIED).read_text())
    rust=base/'tun2proxy-ios-no-tproxy-research-20261115';rm=json.loads(verify(rust,'manifest.json',RECEIPT).read_text())
    for n,d in rm['files'].items():verify(rust,n,d)
    assert rm['archive_sha256']==ARCHIVE and len(rm['notice_inventory'])==141 and not rm['missing_original_notice_in_source_inventory']
    with tempfile.TemporaryDirectory(prefix='.apl-no-tproxy-review-',dir=out.parent) as tmp:
        w=pathlib.Path(tmp);p=w/'review';p.mkdir();candidates={}
        for label,(name,digest) in CANDIDATES.items():
            folder=base/name;mp=verify(folder,'manifest.json',digest);m=json.loads(mp.read_text())
            assert m['rust_research_receipt_sha256']==RECEIPT and m['inputs']['Lib/Rust/libtun2proxy.a']==ARCHIVE and m['inputs']['Lib/Unified/libAPLUnified.a']==gm['files']['libAPLUnified.a'] and m['synthetic_split_route_compiled']==(label=='split') and not m['release_authorized']
            for file,key in [('build.log','build_log_sha256'),('symbols.txt','symbol_table_sha256')]:verify(folder,file,m[key])
            verify(folder,'host-symbols.txt',m['containing_host']['symbols_sha256']);copy_verified(folder,'manifest.json',digest,p/'candidates'/f'{label}.json')
            if label=='split':verify(folder,'provider-link-map.txt',m['provider_link_map_sha256'])
            candidates[label]={'manifest_sha256':digest,'binary_sha256':m['binary_sha256'],'host_sha256':m['containing_host']['binary_sha256']}
        for name,d in previous['files'].items():
            if name.startswith(('xray/','awg/','mpl/','sdk/')) or name.startswith('source/') and not ('tun2proxy-' in name or name.endswith('Cargo.lock')):
                copy_verified(old,name,d,p/name)
        put(p/'go/unified-manifest.json',(u/'manifest.json').read_bytes())
        for name in ('go.mod','go.sum'):copy_verified(u,name,gm['files'][name],p/'go'/name)
        xr=base/'xray-source-20261115/libxray';xcommit=gm['xray_commit']
        for name,d in gm['unified_bridge_sha256'].items():
            if name.startswith('awg_'):
                data=(p/'source/awg-bridge'/name[4:]).read_bytes()
                if name=='awg_main.go':data=data.replace(b'func main() {',b'func awgSyntheticCLI() {',1)
            else:data=subprocess.check_output(['git','-C',str(xr),'show',xcommit+':cgo_bridge/'+name])
            if hashlib.sha256(data).hexdigest()!=d:raise ValueError('unified bridge mismatch')
            put(p/'go/cgo_bridge'/name,data)
        put(p/'rust/research-manifest.json',(rust/'manifest.json').read_bytes())
        count=0
        for row in rm['notice_inventory']:
            assert row['name']!='tproxy-config' and row['files']
            for f in row['files']:
                copy_verified(rust/'notices',f['path'],f['sha256'],p/'rust/notices'/f['path']);count+=1
        assert count==250
        prepared=w/'prepared';prepare(base/'tun2proxy-source-20261114',prepared)
        new=json.loads((prepared/'preparation.json').read_text());assert new==rm['preparation']
        for name in ('Cargo.toml','Cargo.lock'):assert sha(prepared/'src'/name)==rm['files'][name]
        for name in ('aarch64-apple-ios.tree','aarch64-apple-ios-sim.tree'):
            import re
            def normalized(path):
                lines=path.read_text().splitlines()
                assert re.fullmatch(r'tun2proxy v0\.8\.3 \(/[^\n]+/src\)',lines[0])
                return ['tun2proxy v0.8.3 (ROOT)']+lines[1:]
            assert normalized(prepared/name)==normalized(rust/name),'dependency graph drift'
            copy_verified(rust,name,rm['files'][name],p/'rust'/name)
        archive_tree(prepared/'src',p/'rust/prepared-ios-source.zip')
        recipe=['prepare_ios_rust_without_tproxy.py','fetch_tun2proxy.py','tun2proxy-v0.8.3.Cargo.lock','NativeTunnelLab/ios_dns_address_classification.rs','NativeTunnelLab/tun2proxy-connected-udp-loopback-clean.patch']
        recipe += [x.name for x in ROOT.joinpath('Tools').glob('tun2proxy-*.patch')]
        for name in sorted(set(recipe)):put(p/'rust/recipe'/name,(ROOT/'Tools'/name).read_bytes())
        report={'schema':1,'release_authorized':False,'runtime_authorized':False,'scope':'exact private source/notice review; SDK materials separate historical baseline; not final distribution or installed binary provenance','candidates':candidates,'rust_archive_sha256':ARCHIVE,'go_archive_sha256':gm['files']['libAPLUnified.a'],'rust_notice_files':count,'go_notice_files':go['original_xray_notice_files']+go['additional_awg_notice_files'],'mpl_archives':3,'source_normalization':'.dockerignore symlink to .gitignore stored as regular identical content','remaining':['final linked component and corresponding-source obligations','SDK applicability, opaque binary and Apple5.4 data behavior','signed physical acceptance','final public delivery approval'],'files':{f.relative_to(p).as_posix():sha(f) for f in sorted(p.rglob('*')) if f.is_file()}}
        put(p/'manifest.json',(json.dumps(report,sort_keys=True,indent=2)+'\n').encode());verify_review(p);p.rename(out)
    return report

if __name__=='__main__':
    if len(sys.argv)==3 and sys.argv[1]=='--verify':print('PRIVATE_REVIEW_VERIFIED',len(verify_review(pathlib.Path(sys.argv[2]))['files']))
    elif len(sys.argv)==3:
        r=stage(pathlib.Path(sys.argv[1]).resolve(),pathlib.Path(sys.argv[2]).absolute());print('PRIVATE_NO_TPROXY_REVIEW_STAGED',len(r['files']),r['rust_notice_files'],r['go_notice_files'])
    else:raise SystemExit('usage: stage_no_tproxy_source_review.py ARTIFACT_ROOT NEW_DIR | --verify DIR')
