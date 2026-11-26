#!/usr/bin/env python3
"""Pin and stage the independent research archive; never install a framework."""
import hashlib,json,mmap,pathlib,shutil,sys
RECEIPT='b119b60c5fead049525aa6243b51d4ba18749bca77d08c497964973e3de49503'
ARCHIVE='782add5ca2c482423cd4ad34aff9f5116ce39023c477fed08d0181d63ce3d807'
HEADERS={'module.modulemap':'14eee827712dd8d1a53c909720ba3b36d2fdf02c8c114c2f9f2451f5f86598b8','tun2proxy.h':'1c280dda963a6df381545d7ecca093830d417421e8424aa6ee7223a00c75de58','tun2proxy.modulemap':'bb7f026c68ddbac2064c51319d0912f14acefe618999e04ccb3d44b3c1cdf132'}
def sha(p):
    if not p.is_file() or p.is_symlink():raise ValueError('invalid file')
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def verify(root,dest):
    if sha(root/'manifest.json')!=RECEIPT:raise ValueError('unreviewed research receipt')
    m=json.loads((root/'manifest.json').read_text());assert m['runtime_authorized'] is False and m['release_authorized'] is False and m['archive_sha256']==ARCHIVE
    for name,d in m['files'].items():
        assert pathlib.Path(name).name==name and sha(root/name)==d
    rows=m['notice_inventory'];assert len(rows)==141 and sum(len(r['files']) for r in rows)==250 and not m['missing_original_notice_in_source_inventory']
    for r in rows:
        assert r['name']!='tproxy-config' and r['files']
        for f in r['files']:
            p=root/'notices'/f['path'];assert p.resolve().is_relative_to((root/'notices').resolve()) and sha(p)==f['sha256']
    for name,d in HEADERS.items():assert sha(dest/'Headers'/name)==d
    lib=root/'libtun2proxy.a';assert sha(lib)==ARCHIVE
    with lib.open('rb') as f,mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as b:assert b.find(b'Forcing exit now.')<0
    for name in ('aarch64-apple-ios.tree','aarch64-apple-ios-sim.tree'):assert 'tproxy-config v' not in (root/name).read_text()
    shutil.copyfile(lib,dest/'libtun2proxy.a');assert sha(dest/'libtun2proxy.a')==ARCHIVE
    print('VERIFIED_NO_TPROXY_RESEARCH_ARCHIVE',ARCHIVE)
if __name__=='__main__':verify(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]))
