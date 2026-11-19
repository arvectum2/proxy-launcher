#!/usr/bin/env python3
"""Preserve locked original crate evidence without manufacturing missing licenses."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
import tomllib

LOCK = Path(__file__).with_name('tun2proxy-v0.8.3.Cargo.lock')
EXPECTED = {'tun': ('0.8.14', 'WTFPL'), 'tproxy-config': ('7.0.9', 'MIT')}


def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def collect(cache, output, lock=LOCK):
    if output.exists():
        raise ValueError('output exists')
    packages=tomllib.loads(lock.read_text())['package']
    with tempfile.TemporaryDirectory(dir=output.parent,prefix='.rust-notices-') as tmp:
        bundle=Path(tmp)/'bundle';bundle.mkdir(mode=0o700);rows=[]
        for name,(version,license_id) in EXPECTED.items():
            matches=[p for p in packages if p['name']==name and p['version']==version and p.get('source')=='registry+https://github.com/rust-lang/crates.io-index']
            if len(matches)!=1:raise ValueError('missing unique locked crate')
            stem=f'{name}-{version}';archive=cache/(stem+'.crate');checksum=matches[0]['checksum']
            if archive.is_symlink() or not archive.is_file() or digest(archive)!=checksum:raise ValueError('locked crate digest mismatch: '+stem)
            with tarfile.open(archive,'r:gz') as t:
                def read(relative):
                    member=t.getmember(stem+'/'+relative)
                    if not member.isfile() or not 0<member.size<=1_000_000:raise ValueError('invalid crate member')
                    return t.extractfile(member).read()
                cargo=read('Cargo.toml');metadata=tomllib.loads(cargo.decode())['package']
                if (metadata['name'],metadata['version'],metadata['license'])!=(name,version,license_id):raise ValueError('crate metadata mismatch')
                vcs=read('.cargo_vcs_info.json');sha=json.loads(vcs)['git']['sha1']
                source=read('src/lib.rs')
            folder=bundle/stem;folder.mkdir();files=[]
            for label,raw,origin in [('Cargo.toml',cargo,'Cargo.toml'),('.cargo_vcs_info.json',vcs,'.cargo_vcs_info.json')]:
                p=folder/label;p.write_bytes(raw);files.append({'file':str(p.relative_to(bundle)),'sha256':digest(p),'source':origin})
            notice='declared_only_original_text_missing'
            if name=='tun':
                lines=source.splitlines(keepends=True);header_lines=[]
                for line in lines:
                    if not line.startswith(b'//'):break
                    header_lines.append(line)
                header=b''.join(header_lines)
                if b'Version 2, December 2004' not in header or b'Copyleft' not in header or b'0. You just DO WHAT' not in header or not 1<=len(header_lines)<=30:raise ValueError('expected original license header not found')
                p=folder/'LICENSE-HEADER.original.txt';p.write_bytes(header);files.append({'file':str(p.relative_to(bundle)),'sha256':digest(p),'source':f'src/lib.rs:1-{len(header_lines)} exact bytes','source_sha256':hashlib.sha256(source).hexdigest()});notice='original_source_header_preserved'
            dest=folder/archive.name;shutil.copyfile(archive,dest)
            if digest(dest)!=checksum:raise ValueError('crate copy mismatch')
            rows.append({'name':name,'version':version,'declared_license':license_id,'notice_status':notice,'vcs_commit':sha,'archive':str(dest.relative_to(bundle)),'archive_sha256':checksum,'files':files})
        manifest={'schema':1,'scope':'supplemental locked source evidence; not final binary notices','release_authorized':False,'lock_sha256':digest(lock),'components':rows,'unresolved_original_text':['tproxy-config@7.0.9']}
        (bundle/'manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n');bundle.rename(output)
    return manifest

if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('usage: export_rust_notice_gap_evidence.py CRATE_CACHE NEW_OUTPUT_DIR')
    print(json.dumps(collect(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve()),indent=2))
