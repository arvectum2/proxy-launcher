#!/usr/bin/env python3
"""Read-only lexical and UI-content audit of all 50 iOS catalogs."""
import json,re,collections,pathlib,unicodedata
ROOT=pathlib.Path(__file__).resolve().parents[1]
CODES=json.loads((ROOT/'ios-locales.json').read_text())['languages']
P=re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')
def read(c):
 file=ROOT/'Resources'/f'{c}.lproj'/'Localizable.strings';found=[]
 for line in file.read_text().splitlines():
  if line.startswith('"'):
   m=P.fullmatch(line)
   assert m,(c,line[:160]);found.append(m.groups())
 assert len(found)==155 and len({k for k,v in found})==155,c
 return dict(found)
EN=read('en');FMT=re.compile(r'%(?:\d+\$)?(?:@|s|d|f)')
report={};fails=[]
for c in CODES:
 d=read(c)
 if set(d)!=set(EN):fails.append([c,'missing source key'])
 same=[(k,v) for k,v in d.items() if v.casefold().strip()==EN[k].casefold().strip() and len(v.split())>=4 and len(v)>35]
 long=[(k,v) for k,v in d.items() if len(v)>=180]
 too_short=[(k,v) for k,v in d.items() if len(EN[k])>120 and len(v)<35]
 formats=[k for k,v in d.items() if FMT.findall(v)!=FMT.findall(EN[k])]
 strange=[(k,v) for k,v in d.items() if '\ufffd' in v or '\x00' in v or v.strip()!=v or '  ' in v]
 report[c]={'longUntranslatedEnglish':same,'veryLongUIStrings':len(long),'suspiciouslyShortImportantStrings':too_short,'formatErrors':formats,'whitespaceOrUnicode':strange}
 if (same and c!='en') or formats or strange:fails.append([c,'English/format/whitespace issues',len(same),len(formats),len(strange)])
print('AUDITED',len(report),'LANGUAGES','ISSUES',len(fails))
for c,d in report.items():
 if c!='en' and (d['longUntranslatedEnglish'] or d['suspiciouslyShortImportantStrings'] or d['whitespaceOrUnicode']):
  print('FLAG',c,'untranslated',len(d['longUntranslatedEnglish']),'short',len(d['suspiciouslyShortImportantStrings']),'whitespace',len(d['whitespaceOrUnicode']))
  for k,v in d['longUntranslatedEnglish'][:2]+d['suspiciouslyShortImportantStrings'][:2]:print('  ',repr(k[:64]),'->',repr(v[:100]))
pathlib.Path('/tmp/apl-ios-50-editorial-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
assert not fails,fails[:10]
