#!/usr/bin/env python3
"""Verify exact reviewed delta; caller already verified and staged baseline archive."""
import json,mmap,pathlib,shutil,sys
from verify_ios_no_tproxy_receipt import RECEIPT,ARCHIVE,sha
EXACT_RECEIPT='25d684eef0cfaa5251ac2b5be1165e9b86dcd4ef556a415e0e6558da5ae89f65'
EXACT_ARCHIVE='6aea76be103f0266c54d10e049f6b9a231cc8ccaf25c59c89003bafe61b2ae16'
def verify(root,dest,product_source):
    assert sha(root/'manifest.json')==EXACT_RECEIPT
    m=json.loads((root/'manifest.json').read_text())
    assert m['base_receipt_sha256']==RECEIPT and m['base_archive_sha256']==ARCHIVE
    assert not m['runtime_authorized'] and not m['release_authorized'] and m['dependency_graph_unchanged']
    assert m['archive_sha256']==EXACT_ARCHIVE and sha(dest/'libtun2proxy.a')==ARCHIVE
    for n,h in m['files'].items():assert pathlib.Path(n).name==n and sha(root/n)==h
    source=json.loads((root/'exact-dns-source.json').read_text())
    assert source['script_sha256']==sha(product_source/'Tools/prepare_native_exact_dns.py')
    archive=root/'libtun2proxy.a';assert sha(archive)==EXACT_ARCHIVE
    with archive.open('rb') as f,mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as b:
        assert b.find(b'native-exact-dns')>=0 and b.find(b'Forcing exit now.')<0
    shutil.copyfile(archive,dest/'libtun2proxy.a');assert sha(dest/'libtun2proxy.a')==EXACT_ARCHIVE
    print('VERIFIED_NATIVE_EXACT_DNS_ARCHIVE',EXACT_ARCHIVE)
if __name__=='__main__':verify(*map(pathlib.Path,sys.argv[1:]))
