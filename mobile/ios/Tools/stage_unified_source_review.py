#!/usr/bin/env python3
"""Private, candidate-bound source/notice staging; never a release package."""
import hashlib,json,os,pathlib,re,shutil,subprocess,sys,tempfile
from audit_native_candidate_evidence import audit,verify,PIN
from audit_unified_go_notices import audit as audit_go,AWG_MODULE
from unified_synthetic_fixture import CANDIDATE
ROOT=pathlib.Path(__file__).resolve().parents[1]

def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def git(p,*args):return subprocess.check_output(['git','-C',str(p),*args],timeout=30)
def put(dst,b):
    dst.parent.mkdir(parents=True,exist_ok=True)
    with dst.open('xb') as f:f.write(b)

def copy_verified(base,name,expected,dest):
    src=verify(base,name,expected);dest.parent.mkdir(parents=True,exist_ok=True)
    with src.open('rb') as a,dest.open('xb') as b:shutil.copyfileobj(a,b)
    if sha(dest)!=expected:raise ValueError('copied file drift')

def verify_staged_review(p):
    import stat,zipfile
    if p.is_symlink() or not p.is_dir() or stat.S_IMODE(p.stat().st_mode)&0o077:raise ValueError('not a private review directory')
    manifest=p/'manifest.json'
    if manifest.is_symlink() or not manifest.is_file() or stat.S_IMODE(manifest.stat().st_mode)&0o077:raise ValueError('unsafe manifest')
    m=json.loads(manifest.read_text())
    if m['schema']!=1 or m['release_authorized'] is not False or m['native_candidate_sha256']!=CANDIDATE:raise ValueError('wrong review scope')
    seen=set()
    for f in p.rglob('*'):
        if f.is_symlink() or stat.S_IMODE(f.stat().st_mode)&0o077:raise ValueError('non-private or symlink entry')
        if f.is_file() and f!=p/'manifest.json':
            rel=f.relative_to(p).as_posix();seen.add(rel)
            if sha(f)!=m['files'].get(rel):raise ValueError('review file drift: '+rel)
    if seen!=set(m['files']):raise ValueError('missing review file')
    if sha(p/'candidate-compile-manifest.json')!=CANDIDATE:raise ValueError('candidate manifest drift')
    for name in seen:
        if name.endswith('.zip'):
            with zipfile.ZipFile(p/name) as z:
                entries=set()
                for member in z.infolist():
                    rel=pathlib.PurePosixPath(member.filename)
                    if rel.is_absolute() or '..' in rel.parts or '\\' in member.filename or member.filename in entries or stat.S_ISLNK(member.external_attr>>16):raise ValueError('unsafe source archive')
                    entries.add(member.filename)
                if z.testzip() is not None:raise ValueError('archive CRC mismatch')
    return m

def stage(base,derived,out):
    if out.exists() or out.is_symlink():raise ValueError('output exists')
    os.umask(0o077)
    old=audit(base,json.loads(PIN.read_text()));go=audit_go(base)
    receipt='product-unified-runtime-backup-evidence-20261115'
    path=verify(base,receipt+'/manifest.json',CANDIDATE);m=json.loads(path.read_text())
    if m['release_authorized'] or not m['synthetic_runtime_compiled']:raise ValueError('wrong candidate')
    for name,expected in [('build.log',m['build_log_sha256']),('symbols.txt',m['symbol_table_sha256'])]:verify(path.parent,name,expected)
    origins={'XrayWireGuardLabConfig.swift':'Tools/XrayWireGuardLabConfig.swift','ExactLabTUNDescriptor.swift':'Tools/NativeTunnelLab/ExactLabTUNDescriptor.swift','AWGPacketFlowPump.swift':'Tools/AWGNativeLab/PacketTunnel/AWGPacketFlowPump.swift'}
    for name,expected in m['sources'].items():verify(ROOT,origins[pathlib.Path(name).name] if name.startswith('FixtureSupport/') else name,expected)
    for rel,src in [('Lib/Unified/libAPLUnified.a','product-unified-go-link-evidence-20261115/libAPLUnified.a'),('Lib/Rust/libtun2proxy.a','tun2proxy-v0.8.3-loopback-udp-clean-20261114/tun2proxy.xcframework/ios-arm64/libtun2proxy.a')]:verify(base,src,m['inputs'][rel])
    pins=json.loads(PIN.read_text())['inventories'];sources=[];sdk=[];notice_count=0
    with tempfile.TemporaryDirectory(prefix='.apl-source-review-',dir=out.parent) as tmp:
        p=pathlib.Path(tmp)/'review';p.mkdir()
        put(p/'candidate-compile-manifest.json',path.read_bytes())
        for label in ('xray','awg','rust','mpl'):
            spec=pins[label];mp=verify(base,spec['path'],spec['sha256']);inv=json.loads(mp.read_text())
            selected=[]
            for row in inv['modules' if label=='xray' else 'components']:
                if label=='awg' and row['module']!=AWG_MODULE:continue
                selected.append(row)
                for f in ([row] if label=='mpl' else row['files']):
                    name=f.get('file',f.get('path'));copy_verified(mp.parent,name,f['sha256'],p/label/name)
                    if label!='mpl':notice_count+=1
            put(p/label/'selected-inventory.json',json.dumps({'origin_manifest_sha256':spec['sha256'],'components':selected},indent=2,sort_keys=True).encode())
        supp=json.loads(PIN.read_text())['rust_supplement'];mp=verify(base,supp['path'],supp['sha256']);inv=json.loads(mp.read_text())
        for row in inv['components']:
            for f in [{'file':row['archive'],'sha256':row['archive_sha256']}]+row['files']:
                copy_verified(mp.parent,f['file'],f['sha256'],p/'rust-supplement'/f['file'])
                if f['file'].endswith('LICENSE-HEADER.original.txt'):notice_count+=1
        put(p/'rust-supplement/manifest.json',mp.read_bytes())
        for label,src,commit in [('libxray','xray-source-20261115/libxray','5a0f7d8d1c28b34afb5727b04b26a10f6dbac7e3'),('awg','awg-source-20261114/awg','b5928efb6ca19f0153958460c3d141f04abc5c2e'),('tun2proxy','tun2proxy-source-20261114','e271de19683937f23d3f8f0eb4df0a61fc4a6e50')]:
            repo=base/src
            if git(repo,'rev-parse','HEAD').decode().strip()!=commit or git(repo,'status','--porcelain'):raise ValueError('source drift')
            dest=p/'source'/f'{label}-{commit}.zip';dest.parent.mkdir(exist_ok=True)
            git(repo,'archive','--format=zip','-o',str(dest),commit)
            normalization=[]
            if label=='tun2proxy':
                import zipfile,stat
                # One exact upstream symlink; preserve provenance but make
                # the review archive safe to unpack on any platform.
                raw=dest.with_suffix('.raw');dest.rename(raw)
                target=git(repo,'show',commit+':.dockerignore')
                if target!=b'.gitignore':raise ValueError('unexpected source symlink')
                regular=git(repo,'show',commit+':.gitignore')
                with zipfile.ZipFile(raw) as original,zipfile.ZipFile(dest,'x') as normalized:
                    for entry in original.infolist():
                        data=original.read(entry)
                        if stat.S_ISLNK(entry.external_attr>>16):
                            if entry.filename!='.dockerignore' or data!=target:raise ValueError('unexpected source symlink')
                            entry.external_attr=(stat.S_IFREG|0o644)<<16
                            data=regular
                            normalization.append({'path':'.dockerignore','original_type':'symlink','target':'.gitignore','original_link_blob_sha256':hashlib.sha256(target).hexdigest(),'regularized_content_sha256':hashlib.sha256(regular).hexdigest()})
                        normalized.writestr(entry,data)
                if len(normalization)!=1:raise ValueError('expected source symlink missing')
                raw.unlink()
            sources.append({'component':label,'commit':commit,'sha256':sha(dest),'normalization':normalization})
        unified=base/'product-unified-go-link-evidence-20261115';um=json.loads((unified/'manifest.json').read_text())
        for name,d in um['original_bridge_sha256'].items():copy_verified(ROOT/'Tools/AWGNativeLab',name,d,p/'source/awg-bridge'/name)
        for name in ('go.mod','go.sum'):copy_verified(unified,name,um['files'][name],p/'source/unified-private'/name)
        patch='Tools/NativeTunnelLab/tun2proxy-connected-udp-loopback-clean.patch';patchsha='9df06d0c3a04d22f981c32750a228014a031506827f8b2ad0c063d0b56e68cab';copy_verified(ROOT,patch,patchsha,p/'source'/pathlib.Path(patch).name)
        lock='Tools/tun2proxy-v0.8.3.Cargo.lock';copy_verified(ROOT,lock,inv['lock_sha256'],p/'source/Cargo.lock')
        for name in ('build_unified_go_candidate_unsigned.sh','build_xray_pinned_source_ios.sh'):put(p/'source/build'/name,(ROOT/'Tools'/name).read_bytes())
        lockpath=ROOT/'ArvectumProxyLauncherIOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        lock=json.loads(lockpath.read_text());put(p/'sdk/Package.resolved',lockpath.read_bytes())
        checkout=derived/'SourcePackages/checkouts';checked={x.name.lower():x for x in checkout.iterdir() if x.is_dir()}
        for pin in lock['pins']:
            ident=pin['identity'];repo=checked[ident];rev=pin['state']['revision']
            if git(repo,'rev-parse','HEAD').decode().strip()!=rev or git(repo,'status','--porcelain'):raise ValueError('SDK checkout drift: '+ident)
            originals=[]
            for name in git(repo,'ls-tree','-r','--name-only',rev).decode().splitlines():
                if re.match(r'^(licen[cs]e|copying|notice|patents|copyright|authors|terms)(?:$|[-_.])',pathlib.PurePosixPath(name).name,re.I):
                    if pathlib.PurePosixPath(name).is_absolute() or '..' in pathlib.PurePosixPath(name).parts:raise ValueError('unsafe SDK notice path')
                    data=git(repo,'show',rev+':'+name);put(p/'sdk/notices'/ident/name,data);originals.append({'path':name,'sha256':hashlib.sha256(data).hexdigest()})
            put(p/'sdk/manifests'/ident/'Package.swift',git(repo,'show',rev+':Package.swift'))
            sdk.append({'identity':ident,'revision':rev,'version':pin['state']['version'],'original_source_notice_files':originals,'scope':'resolved dependency only; binary terms and final linkage unverified'})
        app=derived/'Build/Products/Release-iphoneos/Arvectum Proxy Launcher.app'
        binary=app/'Arvectum Proxy Launcher'
        if not binary.is_file() or any(app.rglob('embedded.mobileprovision')):raise ValueError('unsigned baseline missing')
        privacy={}
        import plistlib
        for src in sorted(app.rglob('PrivacyInfo.xcprivacy')):
            rel=src.relative_to(app).as_posix();data=src.read_bytes();doc=plistlib.loads(data)
            if not isinstance(doc,dict):raise ValueError('invalid privacy manifest')
            put(p/'sdk/unsigned-baseline-privacy'/rel,data);privacy[rel]=sha(src)
        framework=app/'Frameworks';frameworks={}
        for fw in sorted(framework.glob('*.framework')):
            exe=fw/fw.stem
            if not exe.is_file():raise ValueError('framework binary missing')
            frameworks[fw.name]=sha(exe)
        dylibs=subprocess.check_output(['xcrun','otool','-L',str(binary)],text=True,timeout=10).splitlines()[1:]
        # Record selected arm64 artifact slices without claiming they are linked.
        artifacts=derived/'SourcePackages/artifacts';slices={}
        for fw in sorted(artifacts.glob('*/*/*.xcframework/ios-arm64/*.framework')):
            exe=fw/fw.stem
            if exe.is_file():slices[fw.relative_to(artifacts).as_posix()]=sha(exe)
        report={'schema':1,'release_authorized':False,'scope':'private source review of exact unsigned native compile candidate and separate ordinary unsigned SDK baseline; not final linked release SBOM or distribution package','native_candidate_sha256':CANDIDATE,'native_binary_sha256':m['binary_sha256'],'library_inputs':m['inputs'],'native_original_notice_files':notice_count,'mpl_module_archives':3,'sources':sources,'go_graph':go,'unresolved_native_notices':old['unresolved_notices'],'sdk_pins':sdk,'sdk_baseline':{'app_sha256':sha(binary),'frameworks':frameworks,'dynamic_dependencies':[x.strip().split(' (',1)[0] for x in dylibs],'privacy_manifest_sha256':privacy,'cached_arm64_slices':slices},'remaining':['tproxy-config@7.0.9 original MIT attribution','selected final binary/link closure and corresponding source obligations review','vendor SDK binary terms, static linkage and privacy disclosures','trusted signed runtime and overall release acceptance'],'files':{f.relative_to(p).as_posix():sha(f) for f in sorted(p.rglob('*')) if f.is_file()}}
        put(p/'manifest.json',(json.dumps(report,sort_keys=True,indent=2)+'\n').encode())
        verify_staged_review(p)
        if out.exists() or out.is_symlink():raise ValueError('output exists')
        p.rename(out)
    return report

if __name__=='__main__':
    if len(sys.argv)==3 and sys.argv[1]=='--verify':
        r=verify_staged_review(pathlib.Path(sys.argv[2]));print('PRIVATE_REVIEW_VERIFIED',len(r['files']));raise SystemExit(0)
    if len(sys.argv)!=4:raise SystemExit('usage: stage_unified_source_review.py ARTIFACT_ROOT DERIVED_DATA NEW_PRIVATE_DIR')
    a,d,o=map(pathlib.Path,sys.argv[1:]);r=stage(a.resolve(),d.resolve(),o.absolute())
    print('PRIVATE_SOURCE_REVIEW_STAGED','native_notices',r['native_original_notice_files'],'sdk_pins',len(r['sdk_pins']),'sdk_notices',sum(len(x['original_source_notice_files']) for x in r['sdk_pins']),'privacy_manifests',len(r['sdk_baseline']['privacy_manifest_sha256']),'files',len(r['files']),'release_authorized',r['release_authorized'])
