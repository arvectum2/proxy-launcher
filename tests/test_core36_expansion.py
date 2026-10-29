"""Core36 Malay, Filipino, Swahili, Romanian, Hungarian source i18n contract."""
import ast,json,re,xml.etree.ElementTree as ET
from pathlib import Path
R=Path(__file__).resolve().parents[1]
LANGS=('ms','fil','sw','ro','hu')
PAT=re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')
FMT=re.compile(r'%(?:\d+\$)?(?:@|s|d|f)')

def ios(c):
    p=R/f'mobile/ios/Resources/{c}.lproj/Localizable.strings'
    return {m.group(1):m.group(2) for line in p.read_text().splitlines() if (m:=PAT.fullmatch(line))}
def android(c):
    p=R/f'mobile/android/app/src/main/res/values-{c}/strings.xml'
    return {x.attrib['name']:x.text or '' for x in ET.parse(p).getroot()}
def desktop():
    astree=ast.parse((R/'desktop_i18n.py').read_text())
    n=next(x.value for x in astree.body if isinstance(x,ast.Assign) and any(getattr(t,'id','')=='CATALOGS' for t in x.targets))
    return ast.literal_eval(n)

def test_all_five_catalogs_keys_parameters_and_safety_messages():
    en_ios=ios('en');en_android=android('en');D=desktop()
    assert len(en_ios)==155 and len(en_android)==104
    for code in LANGS:
        i=ios(code);a=android(code);d=D[code]
        assert len(i)==155 and set(i)==set(en_ios)
        assert len(a)==104 and set(a)==set(en_android)
        assert len(d)==193 and set(d)==set(D['en'])
        assert all(x.strip() and FMT.findall(x)==FMT.findall(en_ios[k]) for k,x in i.items())
        assert all(x.strip() and FMT.findall(x)==FMT.findall(en_android[k]) for k,x in a.items())
        assert all(x.strip() and FMT.findall(x)==FMT.findall(D['en'][k]) for k,x in d.items())
        assert a['app_title']=='Arvectum Proxy Launcher'
        rec=next(v for k,v in d.items() if k.startswith('Предыдущий сеанс завершился некорректно. Нажмите'))
        diag=next(v for k,v in d.items() if k.startswith('предыдущий сеанс. Автоматический сброс'))
        assert d['Восстановить сеть'] in rec
        assert d['Диагностика'] in diag
        for token in ('SOCKS5','HTTPS','Network Extension','Packet Tunnel','gu-st.ru'):
            assert token in ' '.join(i.values()),(code,token)

def test_registry_ui_picker_and_system_locale_matching():
    manifest=json.loads((R/'localization/apl-locales.json').read_text())
    assert len(manifest['languages'])==36 and manifest['languages'][-5:]==list(LANGS)
    swift=(R/'mobile/ios/App/AppLocalization.swift').read_text()
    for c in LANGS:assert f'case {c}' in swift and f'"{c}"' in swift
    for label in ('Bahasa Melayu','Filipino','Kiswahili','Română','Magyar'):
        assert label in swift
    desktop_src=(R/'desktop_i18n.py').read_text()
    for c in LANGS:assert f'"{c}"' in desktop_src
    assert 'android:supportsRtl="true"' in (R/'mobile/android/app/src/main/AndroidManifest.xml').read_text()
