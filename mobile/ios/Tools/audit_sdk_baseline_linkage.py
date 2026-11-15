#!/usr/bin/env python3
"""Exact separate ordinary unsigned baseline linkage-input receipt, not final SBOM."""
import hashlib,json,pathlib,subprocess,sys
from stage_unified_source_review import verify_staged_review,sha
PIN='60ae765c28b900045d7987703beebdfc6fed3f83e63210a9ba2b7f0549a325fc'

def audit(review,derived):
    m=verify_staged_review(review)
    if sha(review/'manifest.json')!=PIN:raise ValueError('review receipt drift')
    products=derived/'Build/Products/Release-iphoneos';binary=products/'Arvectum Proxy Launcher.app/Arvectum Proxy Launcher'
    if sha(binary)!=m['sdk_baseline']['app_sha256']:raise ValueError('baseline binary drift')
    f=derived/'Build/Intermediates.noindex/ArvectumProxyLauncherIOS.build/Release-iphoneos/ArvectumProxyLauncher.build/Objects-normal/arm64/Arvectum Proxy Launcher.LinkFileList'
    lines=f.read_text().splitlines();objects={}
    for line in lines:
        p=pathlib.Path(line)
        if p.parent==products:
            if not p.is_file() or p.is_symlink() or p.suffix!='.o' or p.name in objects:raise ValueError('unexpected link object')
            objects[p.name]=sha(p)
    deps=[x.strip().split(' (',1)[0] for x in subprocess.check_output(['xcrun','otool','-L',str(binary)],text=True,timeout=10).splitlines()[1:]]
    if deps!=m['sdk_baseline']['dynamic_dependencies']:raise ValueError('dynamic link drift')
    return {'schema':1,'release_authorized':False,'scope':'ordinary unsigned baseline 0.2.0 linker input objects; linker dead stripping may remove individual objects or symbols; resolved-only packages not classified as final included/excluded','source_review_sha256':PIN,'app_sha256':sha(binary),'link_file_list_sha256':sha(f),'all_link_file_list_entries':len(lines),'product_link_object_sha256':objects,'dynamic_dependencies':deps,'counts':{'AppMetrica':sum(x.startswith('AppMetrica') for x in objects),'KSCrash':sum(x.startswith('KSCrash') for x in objects),'YandexWrapper':int('YandexMobileAdsWrapper.o' in objects)},'remaining':['vendor terms and privacy declarations','actual combined 0.3.0 final signed linked closure']}

if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('usage: audit_sdk_baseline_linkage.py PRIVATE_REVIEW DERIVED_DATA')
    print(json.dumps(audit(*map(pathlib.Path,sys.argv[1:])),indent=2,sort_keys=True))
