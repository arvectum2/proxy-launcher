#!/usr/bin/env python3
"""Read-only audit of all shipped iOS .strings resources."""
from pathlib import Path
import re, json
BASE=Path(__file__).resolve().parents[1]/'mobile/ios'
RES=BASE/'Resources'
PAT=re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;',re.M)
FMT=re.compile(r'%(?:\d+\$)?[-+#0 ]*(?:\d+)?(?:\.\d+)?(?:hh|ll|h|l|L|z|t|j)?[@diufFeEgGxXosc]')
ALIASES={'Домой':'Главная','Тема':'Тема оформления','Язык':'Язык приложения','Автоматизация':'Автоматизация приложений'}
def read_strings(path):
    pairs=PAT.findall(path.read_text(encoding='utf-8'))
    keys=[k for k,v in pairs]
    return dict(pairs), sorted({k for k in keys if keys.count(k)>1})
def analyze():
    codes=sorted(p.name[:-6] for p in RES.glob('*.lproj'))
    files={};errors=[]
    for code in codes:
        files[code]={}
        for p in (RES/f'{code}.lproj').glob('*.strings'):
            kv,dupe=read_strings(p)
            files[code][p.stem]=kv
            errors += [f'{code}/{p.stem}: duplicate {k}' for k in dupe]
            for k,v in kv.items():
                if FMT.findall(k)!=FMT.findall(v):errors.append(f'{code}/{p.stem}: placeholder {k[:50]}')
                if not v.strip():errors.append(f'{code}/{p.stem}: empty {k[:50]}')
    legacy=files['en']['Localizable'];extra=files['en']['ProfileManagement']
    ru_extra=files['ru']['ProfileManagement'];new=set(extra)-set(legacy)
    code='\n'.join(p.read_text(encoding='utf-8') for p in (BASE/'App').glob('*.swift'))
    used=set(re.findall(r'AppL10n\.tr\(\s*"((?:\\.|[^"\\])+)"',code))
    missing=sorted(used-set(legacy)-set(extra))
    rows=[]
    for lang in codes:
        b=files[lang].get('Localizable',{});x=files[lang].get('ProfileManagement',{})
        rows.append({'locale':lang,'legacy':len(b),'missing_old':len(set(legacy)-set(b)),
                     'new_native':len(new&(set(b)|set(x))),
                     'new_english':len(new-set(b)-set(x)),
                     'native_core_short':sum(bool(x.get(k) or b.get(k) or b.get(a)) for k,a in ALIASES.items()),
                     'short_labels':{k:x.get(k,b.get(k,b.get(a,extra.get(k,k)))) for k,a in ALIASES.items()},
                     'shortcuts':bool(files[lang].get('QuickActions'))})
    return {'count':len(codes),'old_keys':len(legacy),'new_keys':len(new),
            'en_supp':len(extra),'ru_supp':len(ru_extra),
            'quickactions_locales':sum(x['shortcuts'] for x in rows),
            'unhandled_dynamic':missing,'resource_errors':errors,'locales':rows}
if __name__=='__main__':
    import argparse
    q=argparse.ArgumentParser();q.add_argument('--json',action='store_true');a=q.parse_args()
    x=analyze()
    if a.json:print(json.dumps(x,ensure_ascii=False,indent=2))
    else:
        print('locales',x['count'],'old',x['old_keys'],'new',x['new_keys'],'QuickActions',x['quickactions_locales'])
        print('errors',x['resource_errors'],'unhandled_dynamic',x['unhandled_dynamic'])
        for l in x['locales']:
            print(f"{l['locale']:8} old={l['legacy']} new_native={l['new_native']} English_fallback={l['new_english']} short_native={l['native_core_short']}/4")
