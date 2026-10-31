"""Marathi Gujarati Kannada Malayalam Uzbek Latin localized UI source contract."""
import ast
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
R=Path(__file__).resolve().parents[1]
LANGS=('mr','gu','kn','ml','uz')
PAT=re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')
FMT=re.compile(r'%(?:\d+\$)?(?:@|s|d|f)')

def ios(code):
    p=R/f'mobile/ios/Resources/{code}.lproj/Localizable.strings'
    return {m.group(1):m.group(2) for line in p.read_text().splitlines() if (m:=PAT.fullmatch(line))}

def android(code):
    folder='b+uz+Latn' if code=='uz' else code
    p=R/f'mobile/android/app/src/main/res/values-{folder}/strings.xml'
    return {x.attrib['name']:x.text or '' for x in ET.parse(p).getroot()}

def desktop():
    tree=ast.parse((R/'desktop_i18n.py').read_text())
    a=next(n.value for n in tree.body if isinstance(n,ast.Assign) and any(getattr(x,'id','')=='CATALOGS' for x in n.targets))
    return ast.literal_eval(a)

def test_all_complete_catalogs_and_formats():
    i0=ios('en');a0=android('mr');D=desktop()
    assert len(i0)==155 and len(a0)==104
    for lang in LANGS:
        i=ios(lang);a=android(lang);d=D[lang]
        assert len(i)==155 and set(i)==set(i0)
        assert len(a)==104 and set(a)==set(a0)
        assert len(d)==193 and set(d)==set(D['en'])
        assert all(x.strip() and FMT.findall(x)==FMT.findall(i0[k]) for k,x in i.items())
        assert all(x.strip() and FMT.findall(x)==FMT.findall(a0[k]) for k,x in a.items())
        assert a['app_title']=='Arvectum Proxy Launcher'
        assert all(x.strip() and FMT.findall(x)==FMT.findall(D['en'][k]) for k,x in d.items())
        recovery=next(v for k,v in d.items() if k.startswith('Предыдущий сеанс завершился некорректно. Нажмите'))
        assert d['Восстановить сеть'] in recovery
        diagnostics=next(v for k,v in d.items() if k.startswith('предыдущий сеанс. Автоматический сброс'))
        assert d['Диагностика'] in diagnostics
        for token in ('SOCKS5','HTTPS','Network Extension','Packet Tunnel','gu-st.ru'):
            assert token in ' '.join(i.values()),(lang,token)

def test_registry_native_selection_and_uzbek_latin():
    d=json.loads((R/'localization/apl-locales.json').read_text())
    assert len(d['languages'])>=31 and d['languages'][26:31]==list(LANGS)
    src=(R/'mobile/ios/App/AppLocalization.swift').read_text()
    for code in LANGS:assert f'case {code}' in src
    for label in ('मराठी','ગુજરાતી','ಕನ್ನಡ','മലയാളം','Oʻzbekcha (lotin)'):assert label in src
    assert 'id == "uz-cyrl"' in src
    assert '"mr", "gu", "kn", "ml", "uz"' in src
    desktop_src=(R/'desktop_i18n.py').read_text()
    assert 'code.startswith("uz-cyrl")' in desktop_src
    assert '"mr", "gu", "kn", "ml", "uz"' in desktop_src
    assert 'android:supportsRtl="true"' in (R/'mobile/android/app/src/main/AndroidManifest.xml').read_text()
