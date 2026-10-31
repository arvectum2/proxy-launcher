#!/usr/bin/env python3
"""Build export-ready App Store metadata (never calls App Store Connect)."""
import csv, json, pathlib, re
ROOT=pathlib.Path(__file__).resolve().parent
SOURCE=ROOT/'localized-copy.psv'
OUT=ROOT/'metadata'
CANONICAL='Arvectum Proxy Launcher'
APP_CODES={
'ru':'ru','en-US':'en','en-GB':'en','en-AU':'en','en-CA':'en',
'es-ES':'es','es-MX':'es','fr-FR':'fr','fr-CA':'fr','de-DE':'de',
'it':'it','pt-BR':'pt-BR','pt-PT':'pt-PT','ja':'ja','ko':'ko',
'zh-Hans':'zh-Hans','zh-Hant':'zh-Hant','nl-NL':'nl','id':'id','tr':'tr',
'hi':'hi','ar-SA':'ar','vi':'vi','pl':'pl','th':'th','ur-PK':'ur','bn-BD':'bn',
'pa-IN':'pa','ta-IN':'ta','te-IN':'te','mr-IN':'mr','gu-IN':'gu','kn-IN':'kn','ml-IN':'ml','ms':'ms',
'ro':'ro','hu':'hu','cs':'cs','sk':'sk','el':'el','he':'he',
'sv':'sv','da':'da','fi':'fi','no':'nb','hr':'hr','ca':'ca'}
REQUIRED=('locale','subtitle','intro','profiles','exclusions','shortcuts','privacy','disclaimer','keywords','whatsNew')
rows=[]
with SOURCE.open(encoding='utf-8') as stream:
 for parts in csv.reader((line for line in stream if not line.startswith('#')),delimiter='|'):
  assert len(parts)==len(REQUIRED),(len(parts),parts[:2])
  rows.append(dict(zip(REQUIRED,parts)))
assert len(rows)==len(APP_CODES)==47
assert {r['locale'] for r in rows}==set(APP_CODES)
for row in rows:
 locale=row['locale'];name=CANONICAL
 intro=row['intro']
 features=[f"• HTTP, HTTPS CONNECT, SOCKS5",f"• {row['profiles']}",f"• {row['exclusions']}",f"• {row['shortcuts']}",f"• {row['privacy']}"]
 description=intro+'\n\n'+'\n'.join(features)+'\n\n'+row['disclaimer']
 keyword=row['keywords'].replace('，',',').replace('،',',').strip()
 data={'locale':locale,'iosLanguage':APP_CODES[locale],
       'name':name,'subtitle':row['subtitle'],
       'description':description,'keywords':keyword,
       'promotionalText':intro,'whatsNew':row['whatsNew'],
       'supportUrl':'https://arvectum.com/','marketingUrl':'https://arvectum.com/',
       'screenshots':{'01_profiles':row['profiles'],
                      '02_direct_exceptions':row['exclusions'],
                      '03_app_automation':row['shortcuts']}}
 assert len(name)<=30
 assert len(row['subtitle'])<=30,(locale,'subtitle',len(row['subtitle']),row['subtitle'])
 assert len(intro)<=170,(locale,'promotional',len(intro))
 assert len(description)<=4000
 assert len(keyword.encode('utf-8'))<=100,(locale,'keyword bytes',len(keyword.encode('utf-8')))
 assert len(row['whatsNew'])<=4000
 assert len(keyword.split(','))==len(set(k.casefold() for k in keyword.split(','))),locale
 assert all(data[k].strip() for k in ('name','subtitle','description','keywords','promotionalText','whatsNew'))
 folder=OUT/locale;folder.mkdir(parents=True,exist_ok=True)
 for field,fname in [('name','name.txt'),('subtitle','subtitle.txt'),('description','description.txt'),('keywords','keywords.txt'),('promotionalText','promotional_text.txt'),('whatsNew','release_notes.txt')]:
  (folder/fname).write_text(data[field]+'\n',encoding='utf-8')
 (folder/'screenshot_copy.json').write_text(json.dumps(data['screenshots'],ensure_ascii=False,indent=2)+'\n')
 rows_out=globals().setdefault('entries',[])
 rows_out.append(data)
(ROOT/'localizations.json').write_text(json.dumps({'scope':'App Store Connect metadata for iOS only','state':'editorial_source_ready_not_uploaded','appBundleId':'ru.arvectum.proxylauncher.ios','supportedLocaleCount':len(entries),'localizations':entries},ensure_ascii=False,indent=2)+'\n')
print('ASO_LOCALES',len(entries),'TOTAL_FILES',len(entries)*7+1)
print('KEYWORDS_BYTES_MAX',max((len(e['keywords'].encode('utf-8')),e['locale']) for e in entries))
print('SUBTITLE_CHARS_MAX',max((len(e['subtitle']),e['locale']) for e in entries))
