#!/usr/bin/env python3
"""Collect missing original texts from exact published crate VCS commits, no code execution."""
import hashlib
import json
from pathlib import Path
import sys
from urllib.request import Request, urlopen

PINS = {
    'daemonize@0.5.0': ('knsd/daemonize','8a87c0b9e5568d2d57284d68e18ea5f24dcad5fb',{'LICENSE-APACHE':'714f924ebb7736191751768d9e5feb508ad86cfb','LICENSE-MIT':'62b4659a7046f43e2c36f3360629933c9b3694ae'}),
    'etherparse@0.20.3': ('JulianSchmid/etherparse','752f96aaa73a878b3842008d8c501650884ba482',{'LICENSE-APACHE':'4c889c70f896419182b65118caa1753f9f960b5a','LICENSE-MIT':'5f9b3332ed7952b2306944ab9b0d3af7431c0fa0'}),
}

def main(root: Path):
    manifest_path=root/'manifest.json';manifest=json.loads(manifest_path.read_text())
    if manifest.get('schema')!='arvectum.tun2proxy-ios-candidate-source-licenses.v1' or manifest.get('release_authorized') is not False: raise ValueError('not a source inventory')
    transfers=[];rows={f"{c['name']}@{c['version']}":c for c in manifest['components']}
    for key,(repo,commit,files) in PINS.items():
        row=rows[key]
        if row['files']: raise ValueError('supplement already present')
        for name,blob in files.items():
            url=f'https://raw.githubusercontent.com/{repo}/{commit}/{name}'
            with urlopen(Request(url,headers={'User-Agent':'APL-license-inventory'}),timeout=12) as f: data=f.read(1_000_001)
            if not 0<len(data)<=1_000_000 or hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()!=blob: raise ValueError('pinned blob mismatch')
            dest=root/(row['name']+'-'+row['version'])/name
            if dest.exists(): raise ValueError('destination exists')
            transfers.append((row,dest,data,{'path':str(dest.relative_to(root)),'sha256':hashlib.sha256(data).hexdigest(),'source_url':url,'git_blob_sha1':blob,'source_commit':commit}))
    for row,dest,data,entry in transfers:
        dest.write_bytes(data);row['files'].append(entry)
    manifest['missing_root_notice']=[k for k in manifest['missing_root_notice'] if not rows[k]['files']]
    temp=root/'manifest.json.new';temp.write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n');temp.replace(manifest_path)
    print('RUST_UPSTREAM_NOTICE_SUPPLEMENT',len(transfers),'files; unresolved',manifest['missing_root_notice'])

if __name__=='__main__':
    if len(sys.argv)!=2: raise SystemExit('usage: supplement_native_rust_licenses.py INVENTORY_DIR')
    main(Path(sys.argv[1]).resolve())
