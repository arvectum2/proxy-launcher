"""Full additional NL / ID / TR locale resources and semantic safety checks."""
import ast
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGS = ('nl', 'id', 'tr')
IOS = ROOT/'mobile/ios/Resources'
ANDROID = ROOT/'mobile/android/app/src/main/res'
ANDROID_DIRS = {'nl':'values-nl','id':'values-in','tr':'values-tr'}
STRINGS = re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')


def ios(locale):
    return {m.group(1):m.group(2) for line in (IOS/f'{locale}.lproj/Localizable.strings').read_text().splitlines() if (m:=STRINGS.fullmatch(line))}


def android(locale):
    return {x.attrib['name']:x.text for x in ET.parse(ANDROID/ANDROID_DIRS[locale]/'strings.xml').getroot()}


def desktop():
    t=ast.parse((ROOT/'desktop_i18n.py').read_text())
    n=next(n.value for n in t.body if isinstance(n,ast.Assign) and any(isinstance(z,ast.Name) and z.id=='CATALOGS' for z in n.targets))
    return ast.literal_eval(n)


def test_language_registry_and_system_matching():
    registry=json.loads((ROOT/'localization/apl-locales.json').read_text())
    assert len(registry['languages'])>=16
    assert registry['languages'][13:16]==list(LANGS)
    source=(ROOT/'mobile/ios/App/AppLocalization.swift').read_text()
    assert 'case indonesian = "id"' in source
    assert 'case nl' in source and 'case tr' in source
    assert '"nl", "id", "tr"' in source
    assert 'var id: String { rawValue }' in source
    dsrc=(ROOT/'desktop_i18n.py').read_text()
    for lang in LANGS:assert f'"{lang}"' in dsrc


def test_coverage_and_protocol_placeholders():
    base_ios=ios('en')
    base_android=android('nl')
    base_desktop=desktop()['ru']
    for lang in LANGS:
        i=ios(lang);a=android(lang);d=desktop()[lang]
        assert set(i)==set(base_ios) and len(i)==155
        assert set(a)==set(base_android) and len(a)==104
        assert set(d)==set(base_desktop) and len(d)==193
        assert all(t.strip() for t in i.values())
        assert all(t.strip() for t in a.values())
        assert all(t.strip() for t in d.values())
        for key in ('Прокси','Порт','Настройки','Подключиться'):
            assert i[key] and i[key] != key,(lang,key)
        for t in ('gosuslugi.ru','gu-st.ru','www'):
            assert t in i[next(k for k in i if 'gosuslugi.ru' in k)],(lang,t)
        for name in ('Network Extension','Packet Tunnel','HTTP','HTTPS','SOCKS5'):
            assert name in ''.join(i.values()),(lang,name)
        for n in ('apl_apps_bypassing_count','apl_latency_milliseconds','apl_exclusions_saved_count'):
            assert '%1$d' in a[n]
        for n in ('apl_switching_to_profile','apl_error_detail','apl_profile_saved'):
            assert '%1$s' in a[n]
        assert a['app_title']=='Arvectum Proxy Launcher'


def test_same_recovery_button_copy_and_ios_automation_explanation():
    D=desktop()
    ru=D['ru'];key=next(k for k in ru if k.startswith('Предыдущий сеанс завершился некорректно. Нажмите'))
    for lang in LANGS:
        assert D[lang]['Восстановить сеть'] in D[lang][key]
        texts=ios(lang)
        step1=next(v for k,v in texts.items() if k.startswith('1. «Приложение'))
        step2=next(v for k,v in texts.items() if k.startswith('2. «Приложение'))
        assert 'APL' in step1 and 'APL' in step2
        assert 'APL' in texts[next(k for k in texts if k.startswith('Apple не предоставляет приложению'))]
