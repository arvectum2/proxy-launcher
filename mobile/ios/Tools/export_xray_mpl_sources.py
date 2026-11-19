#!/usr/bin/env python3
"""Export exact cached MPL module source archives for the candidate, not legal clearance."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

MODULES = ('github.com/xtls/xray-core', 'github.com/xtls/reality', 'layeh.com/gopher-luar')
PIN = Path(__file__).with_name('xray_source_pins.json')


def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def decode_stream(text):
    decoder=json.JSONDecoder();pos=0
    while pos<len(text):
        while pos<len(text) and text[pos].isspace():pos+=1
        if pos==len(text):break
        row,pos=decoder.raw_decode(text,pos);yield row


def check_rows(rows, lock, cache):
    found={r['Path']:r for r in rows}
    if len(rows)!=len(MODULES) or set(found)!=set(MODULES):raise ValueError('module set mismatch')
    result=[]
    for name in MODULES:
        row=found[name];version=row['Version']
        if row.get('Error') or not version.startswith('v'):raise ValueError('module metadata rejected')
        for suffix,field in [('', 'Sum'),('/go.mod','GoModSum')]:
            if (name,version+suffix,row.get(field)) not in lock:raise ValueError('locked sum mismatch')
        z=Path(row['Zip']).resolve()
        if not z.is_relative_to(cache.resolve()) or not z.is_file():raise ValueError('archive outside verified cache')
        with zipfile.ZipFile(z) as f:
            prefix=name+'@'+version+'/'
            if not f.namelist() or any(not p.startswith(prefix) or '..' in p.split('/') for p in f.namelist()):raise ValueError('unexpected archive paths')
            if f.testzip() is not None:raise ValueError('invalid zip CRC')
            licenses=[p for p in f.namelist() if p==prefix+'LICENSE' or p==prefix+'LICENSE.md' or p==prefix+'LICENSE.txt']
            if not any(b'Mozilla Public License' in f.read(p) for p in licenses):raise ValueError('MPL notice not found')
        result.append((row,z))
    return result


def export(base, output):
    pin=json.loads(PIN.read_text());src=base/'libxray';cache=base/'modcache';go=base/'go/bin/go'
    if output.exists():raise ValueError('output already exists')
    if sha(base/pin['go_archive'])!=pin['go_archive_sha256'] or sha(src/'go.mod')!=pin['go_mod_sha256'] or sha(src/'go.sum')!=pin['go_sum_sha256']:raise ValueError('source/toolchain pin mismatch')
    def git(*args):return subprocess.check_output(['git','-C',str(src),*args],text=True).strip()
    if git('rev-parse','HEAD')!=pin['source_commit'] or git('status','--porcelain'):raise ValueError('source checkout mismatch')
    env=dict(os.environ,GOTOOLCHAIN='local',GOWORK='off',GOENV='off',GOPATH=str(base/'gopath'),GOMODCACHE=str(cache),GOCACHE=str(base/'gocache'),GOPROXY='off',GOSUMDB='sum.golang.org',GOPRIVATE='',GONOSUMDB='',GONOPROXY='')
    if subprocess.check_output([str(go),'version'],env=env,text=True).strip()!='go version go1.27.3 darwin/arm64':raise ValueError('toolchain version mismatch')
    subprocess.run([str(go),'mod','verify'],cwd=src,env=env,check=True)
    raw=subprocess.check_output([str(go),'mod','download','-json',*MODULES],cwd=src,env=env,text=True)
    lock={tuple(line.split()) for line in (src/'go.sum').read_text().splitlines()}
    verified=check_rows(list(decode_stream(raw)),lock,cache)
    with tempfile.TemporaryDirectory(dir=output.parent,prefix='.mpl-source-') as temp:
        w=Path(temp)/'bundle';w.mkdir(mode=0o700);entries=[]
        for row,z in verified:
            filename=row['Path'].replace('/','_')+'@'+row['Version']+'.zip';dest=w/filename
            shutil.copyfile(z,dest)
            if sha(z)!=sha(dest):raise ValueError('archive copy mismatch')
            entries.append({'module':row['Path'],'version':row['Version'],'go_sum':row['Sum'],'go_mod_sum':row['GoModSum'],'file':filename,'sha256':sha(dest),'bytes':dest.stat().st_size})
        shutil.copyfile(src/'go.sum',w/'go.sum');shutil.copyfile(src/'go.mod',w/'go.mod')
        manifest={'scope':'local source candidate, source correspondence only','release_authorized':False,'source_commit':pin['source_commit'],'go_sum_sha256':pin['go_sum_sha256'],'go_mod_sha256':pin['go_mod_sha256'],'components':entries}
        (w/'manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n');w.rename(output)
    print('MPL_SOURCE_ARCHIVES_VERIFIED',len(entries))

if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('usage: export_xray_mpl_sources.py VERIFIED_SOURCE_DIR NEW_OUTPUT_DIR')
    export(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
