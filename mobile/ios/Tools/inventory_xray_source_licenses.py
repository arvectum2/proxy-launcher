#!/usr/bin/env python3
"""Inventory verified iOS source dependency graph, not a final binary SBOM."""
import hashlib
import json
import pathlib
import re
import shutil
import sys


def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f,'sha256').hexdigest()


def inventory(graph, go_root, output):
    if output.exists():
        raise ValueError('output must not exist')
    text=graph.read_text(); decoder=json.JSONDecoder(); pos=0; packages=0; modules={}; package_dirs={}
    while pos<len(text):
        while pos<len(text) and text[pos].isspace(): pos+=1
        if pos==len(text): break
        p,pos=decoder.raw_decode(text,pos); packages+=1
        if p.get('Error') or p.get('DepsErrors'): raise ValueError('incomplete dependency graph')
        if p.get('Module'):
            m=p['Module']
            if m.get('Replace'): raise ValueError('unexpected module replacement')
            key=m['Path']; identity=(m.get('Version','main'),m['Dir'])
            if key in modules and modules[key]!=identity: raise ValueError('conflicting module identities')
            modules[key]=identity
            if p.get('Dir'):
                root=pathlib.Path(m['Dir']).resolve(); directory=pathlib.Path(p['Dir']).resolve()
                if not directory.is_relative_to(root): raise ValueError('package outside module')
                while directory != root:
                    package_dirs.setdefault(key,set()).add(directory);directory=directory.parent
    if not packages or not modules: raise ValueError('empty graph')
    modules['Go standard library and runtime']=('go1.27.3',str(go_root))
    rows=[]; output.mkdir(mode=0o700)
    for n,(version,directory) in sorted(modules.items()):
        root=pathlib.Path(directory)
        folder=output/(hashlib.sha256(n.encode()).hexdigest()[:16]); folder.mkdir()
        files=[]
        root=root.resolve()
        for directory in [root]+sorted(package_dirs.get(n,set())):
            for p in sorted(directory.iterdir()):
                if p.is_file() and not p.is_symlink() and re.match(r'^(licen[cs]e|copying|notice|patents|copyright|authors)(?:$|[-_.])',p.name,re.I):
                    dest=folder/p.relative_to(root);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dest)
                    files.append({'file':str(dest.relative_to(output)),'sha256':digest(dest),'module_relative_path':str(p.relative_to(root))})
        if not any(re.match(r'^(licen[cs]e|copying)',pathlib.Path(f['file']).name,re.I) for f in files): raise ValueError('missing original license: '+n)
        rows.append({'module':n,'version':version,'files':files})
    result={'scope':'ios-arm64 cgo_bridge source graph; module roots and ancestors of compiled package directories; not binary clearance','packages':packages,'modules':rows,'graph_sha256':digest(graph)}
    (output/'manifest.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'packages':packages,'components_including_go':len(rows),'files':sum(len(r['files']) for r in rows)}))

if __name__=='__main__':
    if len(sys.argv)!=4: raise SystemExit('usage: inventory_xray_source_licenses.py GRAPH GO_ROOT NEW_OUTPUT_DIR')
    inventory(*map(pathlib.Path,sys.argv[1:]))
