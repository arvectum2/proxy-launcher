"""User-facing technical semantics, checked across Core-12 source catalogs."""
import ast
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GLOSSARY = json.loads((ROOT / 'localization/editorial-glossary.json').read_text())
LANGS = GLOSSARY['languages']
IOS = ROOT / 'mobile/ios/Resources'
ANDROID = ROOT / 'mobile/android/app/src/main/res'
ANDROID_DIR = {'en':'values-en','ru':'values','es':'values-es','fr':'values-fr','de':'values-de',
               'it':'values-it','ja':'values-ja','ko':'values-ko','pt-BR':'values-pt-rBR',
               'pt-PT':'values-pt-rPT','zh-Hans':'values-b+zh+Hans','zh-Hant':'values-b+zh+Hant'}
PAT = re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')


def ios(lang):
    return {m.group(1):m.group(2) for line in (IOS / f'{lang}.lproj/Localizable.strings').read_text().splitlines()
            if (m:=PAT.fullmatch(line))}


def android(lang):
    return {e.attrib['name']:e.text for e in ET.parse(ANDROID / ANDROID_DIR[lang] / 'strings.xml').getroot()}


def desktop():
    tree=ast.parse((ROOT / 'desktop_i18n.py').read_text())
    node=next(x.value for x in tree.body if isinstance(x,ast.Assign) and
              any(isinstance(t,ast.Name) and t.id=='CATALOGS' for t in x.targets))
    return ast.literal_eval(node)


def test_editorial_glossary_in_all_available_platform_surfaces():
    assert len(LANGS)==12
    rus=android('ru'); desk=desktop()
    for lang in LANGS:
        strings=ios(lang); resources=android(lang)
        for key,values in GLOSSARY['terms'].items():
            expected=values[lang]
            if key in strings: assert strings[key]==expected,(lang,key,strings[key])
            if key in desk[lang]: assert desk[lang][key]==expected,(lang,key,desk[lang][key])
            for resource,value in rus.items():
                if key==value and resource in resources:
                    assert resources[resource]==expected,(lang,key,resource)


def test_vpn_platform_protocols_and_apple_framework_names_are_not_localized_as_generic_words():
    source=list(ios('en'))
    assert len(source)==155
    for lang in LANGS:
        values=ios(lang)
        assert 'Network Extension' in values[source[147]],lang
        assert 'Packet Tunnel' in values[source[152]],lang
        for identifier in ('gosuslugi.ru','gu-st.ru','www','VPN'):
            assert identifier.lower() in values[source[32]].lower(),(lang,identifier)
        for protocol in ('HTTP','HTTPS','SOCKS5'):
            assert protocol in values[source[76]],(lang,protocol)
        assert 'Arvectum' in values[source[150]],lang
        assert 'iOS' in values[source[9]],lang


def test_android_user_status_templates_keep_format_contracts():
    for lang in LANGS:
        cat=android(lang)
        for name,format_token in [('apl_switching_to_profile','%1$s'),
                                   ('apl_profile_saved','%1$s'),('apl_error_detail','%1$s'),
                                   ('apl_apps_bypassing_count','%1$d'),
                                   ('apl_exclusions_saved_count','%1$d'),
                                   ('apl_latency_milliseconds','%1$d')]:
            assert format_token in cat[name],(lang,name)
        assert cat['app_title']=='Arvectum Proxy Launcher'


def test_desktop_safety_copy_avoids_misleading_autoplay_and_magazine_labels():
    catalog=desktop()
    for lang in LANGS:
        translations=catalog[lang]
        assert all('AutoPlay' not in v for v in translations.values()),lang
    for key,value in catalog['en'].items():
        if 'Журнал' in key or 'журнал' in key:
            assert 'Journal' not in value and 'journal' not in value,(key,value)


def test_chinese_auto_and_network_host_are_not_automobile_or_human_host():
    for lang in ('zh-Hans','zh-Hant'):
        cat=ios(lang)
        for key in ('Авто','Прокси','Порт','Хост','Профили'):
            for unwanted in ('汽车','汽車','港口','主持人','型材','代理商'):
                assert unwanted not in cat[key],(lang,key,cat[key])


def test_desktop_recovery_instructions_name_the_actual_button_on_all_languages():
    catalog=desktop()
    source=next(key for key in catalog['ru'] if key.startswith(
        'Предыдущий сеанс завершился некорректно. Нажмите «Восстановить сеть» прямо здесь'))
    for lang in LANGS:
        assert catalog[lang]['Восстановить сеть'] in catalog[lang][source],lang


def test_editorial_forbids_known_machine_translation_false_friends():
    false_friends={'es':('apoderado',), 'fr':('mandataire','procuration'),
                   'de':('Stellvertreter','AutoPlay'),
                   'it':('procura','delega'),
                   'pt-BR':('procurador',), 'pt-PT':('procurador',),
                   'ja':('ジャーナル','港'), 'ko':('저널','항구'),
                   'zh-Hans':('汽车','港口','主持人','型材','代理商','期刊'),
                   'zh-Hant':('汽車','港口','主持人','型材','代理商','期刊')}
    for lang,forbidden in false_friends.items():
        # Check short, label-like strings where a false friend could be
        # interpreted as a different feature or an unsafe user action.
        strings=ios(lang)
        for key,val in strings.items():
            if len(val) < 45:
                for word in forbidden:
                    assert word.lower() not in val.lower(),(lang,key,val,word)
