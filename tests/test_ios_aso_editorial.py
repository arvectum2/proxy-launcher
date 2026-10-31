"""App Store metadata readiness and meaningful iOS UI editorial terminology."""
import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ASO=ROOT/'mobile/ios/ASO'
IOS=ROOT/'mobile/ios/Resources'
EXPECTED={'ru','en-US','en-GB','en-AU','en-CA','es-ES','es-MX','fr-FR','fr-CA','de-DE','it','pt-BR','pt-PT','ja','ko','zh-Hans','zh-Hant','nl-NL','id','tr','hi','ar-SA','vi','pl','th','ur-PK','bn-BD','pa-IN','ta-IN','te-IN','mr-IN','gu-IN','kn-IN','ml-IN','ms','ro','hu','cs','sk','el','he','sv','da','fi','no','hr','ca'}
P=re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')
def catalog(lang):
 p=IOS/f'{lang}.lproj/Localizable.strings'
 return dict(m.groups() for line in p.read_text().splitlines() if (m:=P.fullmatch(line)))

def test_full_47_app_store_locales_and_apple_limits():
 payload=json.loads((ASO/'localizations.json').read_text())
 entries=payload['localizations']
 assert payload['supportedLocaleCount']==47 and len(entries)==47
 assert {x['locale'] for x in entries}==EXPECTED
 assert len({x['iosLanguage'] for x in entries})==42
 names={x['locale']:x['iosLanguage'] for x in entries}
 assert names['no']=='nb' and names['ur-PK']=='ur' and names['bn-BD']=='bn'
 assert names['pa-IN']=='pa' and names['mr-IN']=='mr'
 for x in entries:
  locale=x['locale'];folder=ASO/'metadata'/locale
  assert len(x['name'])<=30 and x['name']=='Arvectum Proxy Launcher'
  assert 5<=len(x['subtitle'])<=30,(locale,x['subtitle'])
  assert 20<=len(x['promotionalText'])<=170
  assert 90<=len(x['description'])<=4000,(locale,len(x['description']))
  assert 4<=len(x['keywords'].encode('utf-8'))<=100
  assert 10<=len(x['whatsNew'])<=4000
  assert all('http' not in k.lower() for k in x['keywords'].split(','))
  assert 'SOCKS5' in x['description'] and 'HTTP' in x['description']
  assert 'https://arvectum.com/'==x['supportUrl']==x['marketingUrl']
  assert set(x['screenshots'])=={'01_profiles','02_direct_exceptions','03_app_automation'}
  for field,file in [('name','name.txt'),('subtitle','subtitle.txt'),('description','description.txt'),('keywords','keywords.txt'),('promotionalText','promotional_text.txt'),('whatsNew','release_notes.txt')]:
   assert (folder/file).read_text().rstrip('\n')==x[field],(locale,field)
  assert json.loads((folder/'screenshot_copy.json').read_text())==x['screenshots']

def test_50_language_ux_editorial_terms_are_not_mistranslated():
 # These were real high-impact semantic failures in the original catalogs,
 # not merely cosmetic alternative terms.
 fixes={
 'ja':('例外設定','ウェブサイトの例外','アプリの例外'),
 'zh-Hans':('例外规则','网站例外','应用例外'),
 'zh-Hant':('例外規則','網站例外','App 例外'),
 'hi':('अपवाद','वेबसाइट अपवाद','ऐप अपवाद'),
 'mr':('अपवाद','संकेतस्थळ अपवाद','ॲप अपवाद'),
 'ur':('استثنا','ویب سائٹ کے استثنا','ایپ کے استثنا'),
 'pa':('ਅਪਵਾਦ','ਵੈੱਬਸਾਈਟ ਅਪਵਾਦ','ਐਪ ਅਪਵਾਦ'),
 'bn':('ব্যতিক্রম','ওয়েবসাইটের ব্যতিক্রম','অ্যাপের ব্যতিক্রম'),
 'cs':('Výjimky','Výjimky pro weby','Výjimky pro aplikace'),
 'sk':('Výnimky','Výnimky pre weby','Výnimky pre aplikácie'),
 'ro':('Excepții','Excepții pentru site-uri','Excepții pentru aplicații'),
 'de':('Ausnahmen','Website-Ausnahmen','App-Ausnahmen'),
 'he':('חריגים','חריגים לאתרים','חריגים ליישומים'),
 'pl':('Wyjątki','Wyjątki witryn','Wyjątki aplikacji'),
 'el':('Εξαιρέσεις','Εξαιρέσεις ιστοτόπων','Εξαιρέσεις εφαρμογών'),
 'kn':('ವಿನಾಯಿತಿಗಳು','ವೆಬ್‌ಸೈಟ್ ವಿನಾಯಿತಿಗಳು','ಆ್ಯಪ್ ವಿನಾಯಿತಿಗಳು'),
 'gu':('અપવાદો','વેબસાઇટ અપવાદો','એપ્લિકેશન અપવાદો')}
 for code,values in fixes.items():
  d=catalog(code)
  for k,v in zip(('Исключения','Исключения сайтов','Исключения приложений'),values):assert d[k]==v,(code,k,d[k])
 assert catalog('id')['Отключить']=='Putuskan sambungan'
 assert catalog('pl')['Отключить']=='Rozłącz'
 assert catalog('ur')['Отключить']=='منقطع کریں'
 assert all(len(catalog(lang))==155 for lang in json.loads((ROOT/'mobile/ios/ios-locales.json').read_text())['languages'])
