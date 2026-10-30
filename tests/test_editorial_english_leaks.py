"""Editorial QA: complete 40 production locales cannot silently reuse long English copy."""
import ast,html,json,re,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PAT=re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')
def ios(code):
    return {m[1]:m[2] for line in (ROOT/f'mobile/ios/Resources/{code}.lproj/Localizable.strings').read_text().splitlines() if (m:=PAT.fullmatch(line))}
def android(code):
    special={'ru':'values','id':'values-in','pt-BR':'values-pt-rBR','pt-PT':'values-pt-rPT','zh-Hans':'values-b+zh+Hans','zh-Hant':'values-b+zh+Hant','pa':'values-b+pa+Guru','uz':'values-b+uz+Latn','he':'values-iw'}
    directory=special.get(code,f'values-{code}')
    return {e.attrib['name']:html.unescape(e.text or '') for e in ET.parse(ROOT/'mobile/android/app/src/main/res'/directory/'strings.xml').getroot()}
def desktop():
    t=ast.parse((ROOT/'desktop_i18n.py').read_text())
    return ast.literal_eval(next(x.value for x in t.body if isinstance(x,ast.Assign) and any(getattr(y,'id','')=='CATALOGS' for y in x.targets)))
def test_no_untranslated_long_english_sentences_in_40_locales():
    D=desktop();languages=json.loads((ROOT/'localization/apl-locales.json').read_text())['languages']
    assert len(languages)==40
    baseline={'ios':ios('en'),'android':android('en'),'desktop':D['en']}
    assert (len(baseline['ios']),len(baseline['android']),len(baseline['desktop']))==(155,104,193)
    for code in languages:
        resources={'ios':ios(code),'android':android(code),'desktop':D[code]}
        for platform,original in baseline.items():
            localized=resources[platform]
            assert set(localized)==set(original),(code,platform)
            for key,en in original.items():
                tr=localized[key]
                assert tr.strip(),(code,platform,key)
                if code not in ('en','ru') and len(en.split())>=4 and len(en)>28:
                    assert tr.casefold().strip()!=en.casefold().strip(),(code,platform,key,en)

def test_critical_french_android_and_uzbek_desktop_review_corrections():
    assert android('fr')['apl_vpn_is_disabled_you_can_connect_65e75']=='Le VPN est désactivé. Vous pouvez vous reconnecter.'
    D=desktop();u=D['uz'];source=D['en']
    for key in ('Системный прокси %s включён и направлен через Arvectum Proxy Launcher. ',
                'Сначала настройте внешний прокси, затем включайте автозапуск.',
                'Сначала укажи IP/порт/логин/пароль внешнего прокси в «Настройки прокси».',
                'Сначала укажите IP/порт/логин/пароль внешнего прокси в «Настройки прокси».'):
        assert u[key]!=source[key]
    assert '%s' in u['Системный прокси %s включён и направлен через Arvectum Proxy Launcher. ']

def test_all_40_autostart_entry_warnings_use_correct_scope_and_log_label():
    D=desktop()
    key=next(k for k in D['ru'] if 'Чужие записи не изменялись.' in k)
    assert key.startswith('\n\n')
    for code,values in D.items():
        text=values[key]
        assert text.startswith('\n\n')
        assert values['Журнал'] in text,(code,text)
        assert '%s' not in text and '%d' not in text
    assert 'Autostart entries belonging to other applications' in D['en'][key]
    assert 'Записи автозапуска других приложений' in D['ru'][key]
    assert 'Autostart-Einträge anderer Anwendungen' in D['de'][key]
    assert 'entrées de démarrage automatique' in D['fr'][key]
    assert 'network settings' not in D['en'][key].lower()
