#!/usr/bin/env python3
"""Private source/binary delta receipt, bound to the previous reviewed dependency lane."""
import json,os,pathlib,shutil,sys,tarfile
from verify_ios_no_tproxy_receipt import RECEIPT,ARCHIVE,sha
def stage(work,base,out,log):
    assert sha(base/'manifest.json')==RECEIPT and sha(base/'libtun2proxy.a')==ARCHIVE
    source=json.loads((work/'exact-dns-source.json').read_text())
    assert source['base_receipt_sha256']==RECEIPT and source['base_archive_sha256']==ARCHIVE
    assert not source['release_authorized'] and not source['runtime_authorized']
    assert source['script_sha256']==sha(pathlib.Path(__file__).with_name('prepare_native_exact_dns.py'))
    assert source['preparation_sha256']==sha(work/'preparation.json')
    for name,h in source['source_sha256'].items():assert sha(work/'src'/name)==h
    for n in ('Cargo.lock','Cargo.toml'):assert sha(work/'src'/n)==sha(base/n)
    for n in ('aarch64-apple-ios.tree','aarch64-apple-ios-sim.tree'):
        a,b=(work/n).read_text().splitlines(),(base/n).read_text().splitlines()
        assert a[0].startswith('tun2proxy v0.8.3 ') and b[0].startswith('tun2proxy v0.8.3 ') and a[1:]==b[1:]
    text=log.read_text();assert 'test result: ok. 1 passed; 0 failed' in text and 'Finished `release` profile' in text
    os.umask(0o077);out.mkdir(mode=0o700)
    for n in ('libtun2proxy.a','exact-dns-source.json','preparation.json','aarch64-apple-ios.tree','aarch64-apple-ios-sim.tree'):shutil.copyfile(work/n,out/n)
    shutil.copyfile(log,out/'build.log')
    with tarfile.open(out/'source.tar.gz','x:gz') as t:
        for name in source['source_sha256']:t.add(work/'src'/name,arcname=name,recursive=False)
        t.add(work/'src/.dockerignore',arcname='.dockerignore',recursive=False)
    with tarfile.open(out/'source.tar.gz','r:gz') as t:
        import hashlib
        for name,h in source['source_sha256'].items():
            assert hashlib.sha256(t.extractfile(name).read()).hexdigest()==h
    m={'schema':1,'base_receipt_sha256':RECEIPT,'base_archive_sha256':ARCHIVE,'archive_sha256':sha(out/'libtun2proxy.a'),'dependency_graph_unchanged':True,'source_manifest_sha256':sha(out/'exact-dns-source.json'),'runtime_authorized':False,'release_authorized':False,'files':{p.name:sha(p) for p in out.iterdir() if p.is_file()}}
    (out/'manifest.json').write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
    print('EXACT_DNS_RECEIPT',sha(out/'manifest.json'),m['archive_sha256'])
if __name__=='__main__':stage(*map(pathlib.Path,sys.argv[1:]))
