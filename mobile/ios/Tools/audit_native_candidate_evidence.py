#!/usr/bin/env python3
"""Read-only integrity audit of pinned local evidence. Never authorizes release."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys

PIN=Path(__file__).with_name('native_candidate_evidence_pins.json')


def verify(root, relative, expected):
    rel=PurePosixPath(relative)
    if rel.is_absolute() or not rel.parts or '..' in rel.parts or '\\' in relative:
        raise ValueError('unsafe evidence path')
    path=root
    for part in rel.parts:
        path=path/part
        if path.is_symlink():raise ValueError('evidence symlink')
    if not path.is_file() or not re.fullmatch('[0-9a-f]{64}',expected):raise ValueError('missing file or invalid digest')
    with path.open('rb') as f:actual=hashlib.file_digest(f,'sha256').hexdigest()
    if actual!=expected:raise ValueError('evidence digest mismatch: '+relative)
    return path


def audit(root, pins):
    if pins.get('schema')!=1 or set(pins['inventories'])!={'xray','mpl','awg','rust'}:raise ValueError('invalid pin set')
    results={}; missing=[]
    for label,spec in pins['inventories'].items():
        mpath=verify(root,spec['path'],spec['sha256']);m=json.loads(mpath.read_text())
        if label!='xray' and m.get('release_authorized') is not False:raise ValueError('unexpected authorization')
        rows=m['modules'] if label=='xray' else m['components'];seen=set();files=set()
        for row in rows:
            key=(row.get('module',row.get('name')),row['version'])
            if not key[0] or key in seen:raise ValueError('duplicate component')
            seen.add(key)
            entries=[row] if label=='mpl' else row['files']
            if not entries:missing.append(f'{key[0]}@{key[1]}')
            for entry in entries:
                name=entry.get('file',entry.get('path'))
                if name in files:raise ValueError('duplicate evidence path')
                files.add(name);verify(mpath.parent,name,entry['sha256'])
        if label=='xray':
            verify(root,'xray-source-20261115/source-build/ios-deps.json',m['graph_sha256'])
        if label=='mpl':
            verify(mpath.parent,'go.sum',m['go_sum_sha256']);verify(mpath.parent,'go.mod',m['go_mod_sha256'])
        if label=='rust' and set(m['missing_root_notice'])!=set(missing):raise ValueError('missing notice declaration drift')
        results[label]={'components':len(rows),'files':len(files)}
    lab=root/pins['lab']['path']
    for name,sha in pins['lab']['sha256s'].items():verify(root,pins['lab']['path']+'/'+name,sha)
    if (lab/'XRAY-ORIGIN').read_text().strip()!='local-source-unsigned-only':raise ValueError('unexpected lab origin')
    entries={}
    for line in (lab/'NATIVE-SHA256SUMS').read_text().splitlines():
        sha,name=line.split('  ',1)
        if name in entries:raise ValueError('duplicate lab receipt')
        entries[name]=sha;verify(lab,name,sha)
    if set(entries)!={'NativeLabHost.app/NativeLabHost','NativeLabHost.app/PlugIns/NativeLab.appex/NativeLab'}:raise ValueError('unexpected lab binary set')
    if any((lab/'NativeLabHost.app').rglob('embedded.mobileprovision')):raise ValueError('unexpected provisioned candidate')
    upstream=json.loads(Path(__file__).with_name('xray_source_pins.json').read_text())['validated_ios_source_candidate']
    verify(root,'xray-source-20261115/source-build/libXray.a',upstream['library_sha256'])
    verify(root,'xray-source-20261115/source-build/libXray.h',upstream['header_sha256'])
    declared=dict((name,sha) for sha,name in (line.split('  ',1) for line in (lab/'XRAY-INPUT-SHA256SUMS').read_text().splitlines()))
    if declared.get('libXray.a')!=upstream['library_sha256'] or declared.get('Headers/libXray.h')!=upstream['header_sha256']:raise ValueError('source input receipt mismatch')
    return {'status':'evidence_integrity_pass','release_authorized':False,'scope':'pinned source inventories and unsigned lab binaries only','inventories':results,'unresolved_notices':sorted(missing),'unsigned_lab_binaries':len(entries),'remaining_gates':['final linked closure and legal review','signed shared Keychain and backup restore','actual source-built iOS data plane and route/DNS acceptance','physical network handoff','CloudKit account/two-device acceptance','production integration and explicit release approval']}

if __name__=='__main__':
    if len(sys.argv)!=2:raise SystemExit('usage: audit_native_candidate_evidence.py ARTIFACT_ROOT')
    print(json.dumps(audit(Path(sys.argv[1]).resolve(),json.loads(PIN.read_text())),indent=2,sort_keys=True))
