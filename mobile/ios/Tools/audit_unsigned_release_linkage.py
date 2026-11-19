#!/usr/bin/env python3
"""Build-bound local evidence, never a distribution or legal clearance gate."""
import collections
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

IOS=Path(__file__).resolve().parents[1]
LOCK=IOS/'ArvectumProxyLauncherIOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
APP='Arvectum Proxy Launcher'
TUNNEL='Arvectum Packet Tunnel'
EXPECTED={'appmetrica-sdk-ios','kscrash','swift-package-manager-google-user-messaging-platform','swift-packages','swift-protobuf','yandex-ads-sdk-ios'}
NOTICE=re.compile(r'^(?:licen[cs]e|copying|notice|copyright|terms)(?:[._-].*|)$',re.I)


def sha(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()


def git(root,*args):
    return subprocess.check_output(['git','-C',str(root),*args])


def link_objects(path, executable):
    raw=path.read_bytes();header,sep,_=raw.partition(b'# Sections:')
    if not sep:raise ValueError('incomplete link map')
    lines=header.decode('utf-8').splitlines()
    if len(lines)<4 or not lines[0].startswith('# Path: ') or Path(lines[0][8:]).resolve()!=executable.resolve() or lines[1:3]!=['# Arch: arm64','# Object files:']:raise ValueError('wrong link map identity')
    rows=[]
    for line in lines[3:]:
        m=re.fullmatch(r'\[\s*\d+\]\s+(.+)',line)
        if not m:raise ValueError('invalid object entry')
        rows.append(m[1])
    if not rows:raise ValueError('empty object list')
    return rows


def collect_notices(checkout,pin,out):
    rev=pin['state']['revision'];identity=pin['identity']
    if git(checkout,'rev-parse','HEAD').decode().strip()!=rev or git(checkout,'status','--porcelain'):raise ValueError('checkout drift: '+identity)
    rows=[]
    for entry in git(checkout,'ls-tree','-rz',rev).split(b'\0'):
        if not entry:continue
        meta,name=entry.split(b'\t',1);rel=PurePosixPath(name.decode('utf-8'))
        if not NOTICE.fullmatch(rel.name):continue
        if rel.is_absolute() or '..' in rel.parts or not meta.startswith((b'100644 blob ',b'100755 blob ')):raise ValueError('unsafe notice entry')
        data=git(checkout,'cat-file','blob',meta.split()[-1].decode())
        if not 0<len(data)<=2_000_000:raise ValueError('invalid notice size')
        dst=out/identity/Path(*rel.parts);dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(data)
        rows.append({'path':str(dst.relative_to(out)),'sha256':sha(dst),'git_blob':meta.split()[-1].decode()})
    return rows


def audit(derived,out):
    if out.exists():raise ValueError('output exists')
    pins=json.loads(LOCK.read_text())['pins']
    if {p['identity'] for p in pins}!=EXPECTED or len(pins)!=len(EXPECTED):raise ValueError('unreviewed package set')
    product=derived/'Build/Products/Release-iphoneos';app=product/(APP+'.app');ext=app/'PlugIns'/(TUNNEL+'.appex')
    intermediates=derived/'Build/Intermediates.noindex/ArvectumProxyLauncherIOS.build/Release-iphoneos'
    maps=[intermediates/'ArvectumProxyLauncher.build'/(APP+'-LinkMap-normal-arm64.txt'),intermediates/'PacketTunnel.build'/(TUNNEL+'-LinkMap-normal-arm64.txt')]
    executable=[app/APP,product/(TUNNEL+'.appex')/TUNNEL]
    a,t=[link_objects(m,e) for m,e in zip(maps,executable)]
    if sha(executable[1])!=sha(ext/TUNNEL):raise ValueError('embedded extension differs')
    info=plistlib.loads((app/'Info.plist').read_bytes());ei=plistlib.loads((ext/'Info.plist').read_bytes())
    version=[info['CFBundleShortVersionString'],info['CFBundleVersion']]
    if version!=[ei['CFBundleShortVersionString'],ei['CFBundleVersion']]:raise ValueError('version mismatch')
    lib=product/'libtun2proxy.a';rust_count=sum('(' in x and Path(x.split('(',1)[0]).resolve()==lib.resolve() for x in t)
    if rust_count==0 or sha(lib)!=sha(IOS/'Frameworks/tun2proxy.xcframework/ios-arm64/libtun2proxy.a'):raise ValueError('Rust archive mismatch')
    ext_objects=collections.Counter(x.split('/Build/Products/Release-iphoneos/',1)[1].split('(')[0].split('/')[0] for x in a if '/Build/Products/Release-iphoneos/' in x)
    frameworks=sorted(x.name for x in (app/'Frameworks').glob('*.framework'))
    if 'YandexMobileAds.framework' not in frameworks or not all(any(k.startswith(prefix) for k in ext_objects) for prefix in ['YandexMobileAds','AppMetrica','KSCrash']):raise ValueError('expected ad linkage missing')
    if any(app.rglob('embedded.mobileprovision')):raise ValueError('provisioned candidate not allowed')
    with tempfile.TemporaryDirectory(dir=out.parent,prefix='.release-evidence-') as tmp:
        stage=Path(tmp)/'bundle';stage.mkdir(mode=0o700);rows=[]
        checkouts=derived/'SourcePackages/checkouts'
        for pin in sorted(pins,key=lambda p:p['identity']):
            name=pin['identity'];matches=[d for d in checkouts.iterdir() if d.name.lower()==name]
            if len(matches)!=1:raise ValueError('missing checkout '+name)
            files=collect_notices(matches[0],pin,stage)
            rows.append({'identity':name,'state':pin['state'],'files':files,'notice_status':'original_blobs_preserved' if files else 'missing_in_checkout','link_evidence':'named_objects' if name in {'yandex-ads-sdk-ios','appmetrica-sdk-ios','kscrash'} else 'resolved_only_not_confirmed_linked'})
        binary_paths=[app/APP,ext/TUNNEL,app/'Frameworks/YandexMobileAds.framework/YandexMobileAds']
        report={'schema':1,'release_authorized':False,'scope':'observed local unsigned default artifact; not final linked SBOM','source_head':git(IOS,'rev-parse','HEAD').decode().strip(),'version':version,'package_resolved_sha256':sha(LOCK),'binary_sha256':{str(p.relative_to(app)):sha(p) for p in binary_paths},'rust_archive_sha256':sha(lib),'rust_archive_members_in_map':rust_count,'link_map_sha256':{m.name:sha(m) for m in maps},'app_external_object_counts':dict(ext_objects),'embedded_frameworks':frameworks,'packages':rows,'remaining':['exact default Rust patch/license closure (research variant differs)','vendor binary/internal dependency and distribution terms review','original tproxy-config MIT notice','final signed artifact and legal approval']}
        maps_dir=stage/'link-maps';maps_dir.mkdir()
        for m in maps:
            dest=maps_dir/m.name;shutil.copyfile(m,dest)
            if sha(dest)!=report['link_map_sha256'][m.name]:raise ValueError('link map copy mismatch')
        (stage/'manifest.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');stage.rename(out)
    return report

if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('usage: audit_unsigned_release_linkage.py DERIVED_DATA NEW_OUTPUT_DIR')
    print(json.dumps(audit(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve()),indent=2,sort_keys=True))
