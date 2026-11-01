#!/usr/bin/env python3
"""Audit all shipped iOS .strings resources, including iOS 0.2 feature tables.

The legacy 155-key catalog stays intact. Format specifiers support the
Foundation positional form %1$d / %2$d for natural word order in translation.
Source/target strings are public app copy; no network or private user data.
"""
from pathlib import Path
import re, json, sys

BASE=Path(__file__).resolve().parents[1]/'mobile/ios'
RES=BASE/'Resources'
PAT=re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;',re.M)
FMT=re.compile(r'%(?:(\d+)\$)?[-+#0 ]*(?:\d+)?(?:\.\d+)?(?:hh|ll|h|l|L|z|t|j)?([@diufFeEgGxXosc])')
ALIASES={'Домой':'Главная','Тема':'Тема оформления','Язык':'Язык приложения','Автоматизация':'Автоматизация приложений'}
REQUIRED_TABLES={'Localizable':155,'ProfileManagement':101,'ProxyImport':40,
                 'SmartExclusions':45,'QuickActions':3}

def read_strings(path):
    pairs=PAT.findall(path.read_text(encoding='utf-8'))
    keys=[k for k,v in pairs]
    return dict(pairs), sorted({k for k in keys if keys.count(k)>1})

def format_error(key,value):
    original=list(FMT.finditer(key))
    translated=list(FMT.finditer(value))
    if len(original)!=len(translated):
        return 'format count'
    if not original:return None
    expected=[m.group(2) for m in original]
    positional=[m for m in translated if m.group(1)]
    if positional:
        if len(positional)!=len(translated):return 'mixed positional/ordinary formats'
        indices=[int(m.group(1)) for m in translated]
        if sorted(indices)!=list(range(1,len(expected)+1)):return 'format indices invalid'
        if any(m.group(2)!=expected[i-1] for i,m in zip(indices,translated)):
            return 'format types out of order'
    elif [m.group(2) for m in translated]!=expected:
        return 'format type'
    return None

def analyze():
    codes=sorted(p.name[:-6] for p in RES.glob('*.lproj'))
    files={};errors=[]
    for code in codes:
        files[code]={}
        for path in (RES/f'{code}.lproj').glob('*.strings'):
            kv,duplicates=read_strings(path)
            files[code][path.stem]=kv
            errors += [f'{code}/{path.stem}: duplicate {k}' for k in duplicates]
            for k,v in kv.items():
                if issue:=format_error(k,v):
                    errors.append(f'{code}/{path.stem}: {issue} {k[:58]}')
                if not v.strip():
                    errors.append(f'{code}/{path.stem}: empty {k[:58]}')
                if re.search(r'87341\d+',v):
                    errors.append(f'{code}/{path.stem}: leaked machine-token {k[:58]}')
                if '\uFFFD' in v:
                    errors.append(f'{code}/{path.stem}: invalid replacement char {k[:58]}')
    original=files['en']['Localizable']
    features=files['en']['ProfileManagement']
    additive=set(features)-set(original)
    app='\n'.join(p.read_text(encoding='utf-8') for p in (BASE/'App').glob('*.swift'))
    used=set(re.findall(r'AppL10n\.tr\(\s*"((?:\\.|[^"\\])+)"',app))
    unused=sorted(used-set(original)-set(features))
    rows=[]
    for code in codes:
        b=files[code].get('Localizable',{})
        p=files[code].get('ProfileManagement',{})
        row={'locale':code,'legacy':len(b),'legacy_missing':len(set(original)-set(b)),
             'new_native':len(additive&(set(b)|set(p))),
             'new_english':len(additive-set(b)-set(p)),
             'shortcuts':bool(files[code].get('QuickActions')),
             'native_core_short':sum(bool(p.get(k) or b.get(k) or b.get(old))
                                     for k,old in ALIASES.items()),
             'short_labels':{k:p.get(k,b.get(k,b.get(old,features.get(k,k))))
                             for k,old in ALIASES.items()}}
        for table,expected_count in REQUIRED_TABLES.items():
            contents=files[code].get(table,{})
            row[table+'_entries']=len(contents)
            if len(contents)!=expected_count:
                errors.append(f'{code}/{table}: {len(contents)}/{expected_count} entries')
            if code!='en':
                unknown=set(contents)-set(files['en'][table])
                missing=set(files['en'][table])-set(contents)
                if unknown:errors.append(f'{code}/{table}: extra keys {len(unknown)}')
                if missing:errors.append(f'{code}/{table}: missing keys {len(missing)}')
        rows.append(row)
    # Machine translated drafts are not silently considered linguistic review.
    unchanged=[]
    for code in codes:
        if code in ('en','ru'):continue
        for table in ('ProfileManagement','ProxyImport','SmartExclusions'):
            for k,v in files[code].get(table,{}).items():
                english=files['en'][table].get(k)
                if english and len(english)>16 and v.casefold()==english.casefold():
                    unchanged.append(f'{code}/{table}: {k[:50]}')
    return {'count':len(codes),'old_keys':len(original),'new_keys':len(additive),
            'en_supp':len(features),'ru_supp':len(files['ru']['ProfileManagement']),
            'quickactions_locales':sum(row['shortcuts'] for row in rows),
            'required_tables':REQUIRED_TABLES,'unhandled_dynamic':unused,
            'resource_errors':errors,'unchanged_english':unchanged,'locales':rows}

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--json',action='store_true')
    args=p.parse_args()
    out=analyze()
    if args.json:print(json.dumps(out,ensure_ascii=False,indent=2))
    else:
        print('locales',out['count'],'old',out['old_keys'],'new',out['new_keys'],
              'QuickActions',out['quickactions_locales'])
        print('Errors',len(out['resource_errors']),'Unknown dynamic keys',len(out['unhandled_dynamic']),
              'Unchanged English feature strings',len(out['unchanged_english']))
        for row in out['locales']:
            print(f"{row['locale']:8} old={row['legacy']} new_native={row['new_native']} "
                  f"English_fallback={row['new_english']} "
                  f"import={row['ProxyImport_entries']} exclusions={row['SmartExclusions_entries']} "
                  f"shortcuts={row['QuickActions_entries']}")
        for issue in (out['resource_errors']+out['unhandled_dynamic']+out['unchanged_english'])[:30]:
            print('ISSUE',issue)
    sys.exit(bool(out['resource_errors'] or out['unhandled_dynamic']))
