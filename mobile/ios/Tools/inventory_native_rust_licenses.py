#!/usr/bin/env python3
"""Source-level iOS normal/build crate closure and original notices; no release clearance."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
PIN = 'e271de19683937f23d3f8f0eb4df0a61fc4a6e50'
TARGET = 'aarch64-apple-ios'


def run(args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True)


def inventory(source, output, cargo):
    if run(['git', '-C', str(source), 'rev-parse', 'HEAD']).strip() != PIN or run(['git', '-C', str(source), 'status', '--porcelain']).strip():
        raise ValueError('Rust source pin/cleanliness mismatch')
    if not output.is_dir() or any(output.iterdir()):
        raise ValueError('empty output directory required')
    spec = importlib.util.spec_from_file_location('pin', ROOT/'fetch_tun2proxy.py')
    pin = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pin)
    patches = [pin.SPLIT_DNS_PATCH, pin.FLOW_INTENT_PATCH, pin.SCOPED_DIRECT_EXPERIMENT_PATCH, pin.SAME_FLOW_RETRY_PATCH, pin.DIRECT_FAMILY_PATCH, ROOT/'NativeTunnelLab/tun2proxy-connected-udp-loopback-clean.patch']
    with tempfile.TemporaryDirectory(prefix='apl-rust-inventory-') as d:
        w = Path(d); src = w/'src'; src.mkdir(); bundle = w/'bundle'; bundle.mkdir()
        archive = w/'source.tar'
        subprocess.run(['git','-C',str(source),'archive','--format=tar','-o',str(archive),PIN],check=True)
        subprocess.run(['tar','-xf',str(archive),'-C',str(src)],check=True)
        shutil.copy2(pin.LOCKFILE, src/'Cargo.lock')
        f = src/'src/general_api.rs'; text=f.read_text(); assert text.count(pin.FORCED_EXIT_BLOCK)==1
        f.write_text(text.replace(pin.FORCED_EXIT_BLOCK,pin.PATCHED_BLOCK,1))
        for p in patches:
            subprocess.run(['git','apply','--check',str(p)],cwd=src,check=True)
            subprocess.run(['git','apply',str(p)],cwd=src,check=True)
        base=[str(cargo),'+1.98.1']
        meta=json.loads(run(base+['metadata','--locked','--offline','--filter-platform',TARGET,'--format-version','1'],src))
        tree=run(base+['tree','--locked','--offline','--target',TARGET,'--edges','normal,build','--prefix','none','--format','{p}'],src)
        keys=set()
        for line in tree.splitlines():
            m=re.match(r'^([\w.-]+) v([^ ]+)(?: |$)',line)
            if not m: raise ValueError('unrecognized cargo tree row')
            keys.add(m.groups())
        packages={(p['name'],p['version']):p for p in meta['packages']}
        if not keys <= packages.keys(): raise ValueError('dependency graph mismatch')
        rows=[]
        for name,version in sorted(keys):
            p=packages[name,version]; directory=Path(p['manifest_path']).parent.resolve(); files=set()
            # Original root notices, and explicitly declared license file.
            for item in directory.iterdir():
                if item.is_file() and re.match(r'^(LICEN[CS]E|COPYING|NOTICE|PATENTS|COPYRIGHT|AUTHORS)(?:$|[-_.])',item.name,re.I): files.add(item.resolve())
            if p.get('license_file'): files.add((directory/p['license_file']).resolve())
            folder=bundle/f'{name}-{version}'; folder.mkdir(); texts=[]
            for f in sorted(files):
                if not f.is_relative_to(directory) or not f.is_file() or not 0 < f.stat().st_size <= 1_000_000: raise ValueError('invalid notice file')
                relative=f.relative_to(directory); target=folder/relative; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(f,target)
                texts.append({'path':str(target.relative_to(bundle)),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
            rows.append({'name':name,'version':version,'source':p.get('source'),'license_expression':p.get('license'),'declared_license_file':p.get('license_file'),'files':texts})
        missing=[f"{r['name']}@{r['version']}" for r in rows if not r['files']]
        result={'schema':'arvectum.tun2proxy-ios-candidate-source-licenses.v1','status':'source_inventory_only','release_authorized':False,'source_commit':PIN,'toolchain':'1.98.1','target':TARGET,'edges':'normal,build; not final binary contents','lock_sha256':hashlib.sha256(pin.LOCKFILE.read_bytes()).hexdigest(),'patches':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in patches},'components':rows,'missing_root_notice':missing}
        (bundle/'manifest.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
        shutil.copytree(bundle,output,dirs_exist_ok=True)
        print('RUST_IOS_SOURCE_INVENTORY',len(rows),'crates',sum(len(r['files']) for r in rows),'notice files',len(missing),'without root notice')
        if missing: print('UNRESOLVED_ROOT_NOTICES',','.join(missing))


if __name__=='__main__':
    if len(sys.argv)!=4: raise SystemExit('usage: inventory_native_rust_licenses.py SOURCE EMPTY_OUTPUT CARGO')
    inventory(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve(),Path(sys.argv[3]).absolute())
