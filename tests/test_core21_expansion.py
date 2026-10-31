"""Full five-language resource and Arabic RTL contracts."""
import ast,json,re,xml.etree.ElementTree as ET
from pathlib import Path
R=Path(__file__).resolve().parents[1]
LANGS=['hi','ar','vi','pl','th']
PAT=re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')
FMT=re.compile(r'%(?:\d+\$)?[sdf@]')
def ios(lang):
 return {m.group(1):m.group(2) for line in (R/f'mobile/ios/Resources/{lang}.lproj/Localizable.strings').read_text().splitlines() if (m:=PAT.fullmatch(line))}
def android(lang):
 return {x.attrib['name']:x.text or '' for x in ET.parse(R/f'mobile/android/app/src/main/res/values-{lang}/strings.xml').getroot()}
def desktop():
 n=next(n.value for n in ast.parse((R/'desktop_i18n.py').read_text()).body if isinstance(n,ast.Assign) and any(getattr(x,'id','')=='CATALOGS' for x in n.targets));return ast.literal_eval(n)
def test_all_source_resources_exact_and_nonempty():
 base=ios('en');a0=android('en');D=desktop()
 for lang in LANGS:
  i=ios(lang);a=android(lang);d=D[lang]
  assert len(i)==155 and set(i)==set(base)
  assert len(a)==104 and set(a)==set(a0)
  assert len(d)==193 and set(d)==set(D['en'])
  assert all(x.strip() and FMT.findall(x)==FMT.findall(base[k]) for k,x in i.items())
  assert all(x.strip() and FMT.findall(x)==FMT.findall(a0[k]) for k,x in a.items())
  assert a['app_title']=='Arvectum Proxy Launcher'
  assert all(x.strip() for x in d.values())
  assert d['Восстановить сеть'] in next(v for k,v in d.items() if k.startswith('Предыдущий сеанс завершился некорректно. Нажмите'))
  for marker in ('SOCKS5','HTTPS','Network Extension','Packet Tunnel','gu-st.ru'):
   assert marker in ''.join(i.values()),(lang,marker)
def test_system_languages_and_arabic_rtl():
 assert json.loads((R/'localization/apl-locales.json').read_text())['languages'][16:21]==LANGS
 src=(R/'mobile/ios/App/AppLocalization.swift').read_text()
 for lang in LANGS:assert f'case {lang}' in src
 swift=(R/'mobile/ios/App/ArvectumProxyLauncherApp.swift').read_text()
 assert '["fa", "ar", "ur", "he"].contains(AppL10n.effectiveLanguage)' in swift
 assert 'android:supportsRtl="true"' in (R/'mobile/android/app/src/main/AndroidManifest.xml').read_text()
 assert 'LANGUAGE in ("fa", "ar", "ur", "he")' in (R/'proxy_gui.py').read_text()
 android=(R/'mobile/android/app/src/main/java/ru/arvectum/proxylauncher/MainActivity.kt').read_text()
 for value in ('hostField.textDirection = View.TEXT_DIRECTION_LTR','portField.textDirection = View.TEXT_DIRECTION_LTR'):
  assert value in android
