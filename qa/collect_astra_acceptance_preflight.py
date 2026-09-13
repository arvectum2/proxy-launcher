#!/usr/bin/env python3
"""Read-only Astra Linux host/package preflight for APL-LNX-010."""
from __future__ import annotations
import argparse, hashlib, os, platform, shutil, subprocess
from pathlib import Path

CI_MARKERS=("CI","GITHUB_ACTIONS","GITLAB_CI","JENKINS_URL","BUILDKITE","TEAMCITY_VERSION")

def _read(path: str) -> str:
    try: return Path(path).read_text(encoding="utf-8",errors="replace").strip()
    except OSError: return ""

def _os_release() -> dict[str,str]:
    result={}
    for raw in _read('/etc/os-release').splitlines():
        if '=' not in raw or raw.lstrip().startswith('#'): continue
        k,v=raw.split('=',1); result[k]=v.strip().strip('"')
    return result

def detect_astra(os_release: dict[str,str], astra_marker: str) -> bool:
    hay=' '.join((os_release.get('ID',''),os_release.get('NAME',''),os_release.get('PRETTY_NAME',''),astra_marker)).lower()
    return 'astra' in hay

def _run(args:list[str]) -> tuple[int,str]:
    try:
        p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,check=False,timeout=15,env={**os.environ,'LC_ALL':'C'})
        return p.returncode,p.stdout.strip()
    except Exception as exc: return 127,f"unavailable: {exc}"

def _sha256(path:Path)->str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''): h.update(chunk)
    return h.hexdigest()

def collect(candidate:Path|None, allow_non_astra:bool)->tuple[dict[str,str],list[str]]:
    osr=_os_release(); marker=_read('/etc/astra_version'); detected=detect_astra(osr,marker)
    virt='unknown'
    if shutil.which('systemd-detect-virt'):
        rc,out=_run(['systemd-detect-virt']); virt=(out or 'unknown') if rc==0 else 'none'
    data={
      'schema':'3','mutation':'false','astra_detected':'yes' if detected else 'no',
      'allow_non_astra':'yes' if allow_non_astra else 'no','virtualization':virt,
      'ci_detected':'yes' if any(os.environ.get(k) for k in CI_MARKERS) else 'no',
      'architecture':platform.machine() or 'unknown','os_id':osr.get('ID','unknown'),
      'os_pretty_name':osr.get('PRETTY_NAME','unknown'),'astra_version':marker or 'unavailable',
      'xdg_session_type':os.environ.get('XDG_SESSION_TYPE','unknown'),
      'xdg_current_desktop':os.environ.get('XDG_CURRENT_DESKTOP','unknown'),
      'display_present':'yes' if os.environ.get('DISPLAY') else 'no',
      'wayland_display_present':'yes' if os.environ.get('WAYLAND_DISPLAY') else 'no',
    }
    details=[]
    nmcli=shutil.which('nmcli')
    data['nmcli']=nmcli or 'unavailable'
    if nmcli:
        _,out=_run([nmcli,'--version']); details += ['nmcli_version='+out]
        rc,out=_run([nmcli,'-t','-f','UUID','connection','show','--active'])
        data['active_connection_count']=str(len([x for x in out.splitlines() if x.strip()])) if rc==0 else '0'
        _,out=_run([nmcli,'general','permissions']); details += ['nmcli_permissions_begin',out,'nmcli_permissions_end']
    else: data['active_connection_count']='0'
    if candidate is not None:
        if candidate.is_file():
            data['candidate_name']=candidate.name; data['candidate_sha256']=_sha256(candidate)
            dpkg=shutil.which('dpkg-deb')
            if dpkg:
                for field,key in [('Package','candidate_package'),('Version','candidate_version'),('Architecture','candidate_architecture')]:
                    _,out=_run([dpkg,'-f',str(candidate),field]); data[key]=out or 'unavailable'
        else: data['candidate_missing']=str(candidate)
    else: data['candidate']='not-supplied'
    for p in ('/sys/class/dmi/id/sys_vendor','/sys/class/dmi/id/product_name','/sys/class/dmi/id/board_name'):
        val=_read(p)
        if val: data['dmi_'+Path(p).name]=val.replace('\n',' ')
    return data,details

def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument('output',nargs='?',default='astra-acceptance-preflight.txt',type=Path); ap.add_argument('candidate',nargs='?',type=Path); ap.add_argument('--allow-non-astra',action='store_true'); ns=ap.parse_args()
    data,details=collect(ns.candidate,ns.allow_non_astra); ns.output.parent.mkdir(parents=True,exist_ok=True)
    lines=['APL-LNX-010 read-only preflight evidence']+[f'{k}={v}' for k,v in data.items()]+['']+details+['','NOTE: collector is read-only; it does not install/remove packages, mutate NetworkManager, elevate privileges, or start the app.']
    ns.output.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    if data['astra_detected']!='yes' and not ns.allow_non_astra:
        print(f'Astra Linux was not detected; evidence written to {ns.output}',file=__import__('sys').stderr); return 3
    if ns.candidate is not None and not ns.candidate.is_file(): return 4
    print(ns.output); return 0
if __name__=='__main__': raise SystemExit(main())
