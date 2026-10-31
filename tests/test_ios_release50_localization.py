"""iOS-only Core-50 source catalogs, locale selection, script and editor contracts."""
from pathlib import Path
import json, re, unicodedata
ROOT=Path(__file__).resolve().parents[1]
IOS=ROOT/'mobile/ios'
CODES=('en','ru','es','fr','de','it','pt-BR','pt-PT','ja','ko','zh-Hans','zh-Hant','fa','nl','id','tr','hi','ar','vi','pl','th','ur','bn','pa','ta','te','mr','gu','kn','ml','uz','ms','fil','sw','ro','hu','cs','sk','el','he','ha','am','sv','da','fi','nb','bg','sr','hr','ca')
NEW=('ha','am','sv','da','fi','nb','bg','sr','hr','ca')
PAT=re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')
FMT=re.compile(r'%(?:\d+\$)?(?:@|s|d|f)')
def pairs(code):
    p=IOS/f'Resources/{code}.lproj/Localizable.strings'; assert p.is_file(),p
    lines=[line for line in p.read_text().splitlines() if line.startswith('"')]
    found=[PAT.fullmatch(line) for line in lines]
    assert all(found),(code,[x for x,m in zip(lines,found) if not m][:5])
    d={m[1]:m[2] for m in found}
    assert len(found)==len(d),(code,'duplicate source keys')
    return d

def test_all_50_ios_catalogs_complete_and_placeholders():
    source=pairs('en')
    manifest=json.loads((IOS/'ios-locales.json').read_text())
    assert manifest['scope']=='ios-only' and manifest['languages']==list(CODES)
    assert manifest['sourceEntriesPerLanguage']==155
    assert len(CODES)==50 and len(source)==155
    for c in CODES:
        catalog=pairs(c)
        assert len(catalog)==155 and set(catalog)==set(source),c
        for key,english in source.items():
            value=catalog[key]
            assert value.strip() and '\ufffd' not in value and '\x00' not in value,(c,key)
            assert FMT.findall(value)==FMT.findall(english),(c,key,'format')
            if c in NEW:
                for token in ('APL','iOS','VPN','HTTP','HTTPS','SOCKS5','Network Extension','Packet Tunnel','host:port','gosuslugi.ru','gu-st.ru'):
                    if token in english: assert token in value,(c,key,token)

def test_new_locales_are_actual_translations_and_written_in_right_script():
    en=pairs('en')
    for c in NEW:
        v=pairs(c)
        unchanged=[x for k,x in en.items() if len(x)>30 and len(x.split())>=4 and x.casefold().strip()==v[k].casefold().strip()]
        assert not unchanged,(c,unchanged[:3])
        assert v['Подключиться']!=v['Отключить']
        assert v['Подключено']!=v['Отключено']
        assert v['Ошибка']!=v['Готово']
    for c,range_ in (('am',('\u1200','\u137f')),('sr',('\u0400','\u04ff')),('bg',('\u0400','\u04ff'))):
        data=' '.join(pairs(c).values());written=sum(1 for x in data if range_[0]<=x<=range_[1])
        assert written>=60,(c,written)
    # Hausa uses Latin; Amharic and Serbian Cyrillic do not need RTL layout.

def test_iOS_system_locale_script_protection_and_50_picker_labels():
    swift=(IOS/'App/AppLocalization.swift').read_text()
    assert '50 fully populated APL iOS source languages' in swift
    for code in NEW:assert 'case '+code+'\n' in swift and '"'+code+'"' in swift
    for label in ('Hausa','አማርኛ','Svenska','Dansk','Suomi','Norsk bokmål','Български','Српски (ћирилица)','Hrvatski','Català'):
        assert 'return "'+label+'"' in swift
    for guard in ('sr-latn','ha-arab','uz-cyrl','pa-arab'):
        assert guard in swift
    assert 'return "nb"' in swift
    app=(IOS/'App/ArvectumProxyLauncherApp.swift').read_text()
    assert '["fa", "ar", "ur", "he"].contains(AppL10n.effectiveLanguage)' in app

def test_ios_critical_connection_and_safety_copy_is_consistent():
    en=pairs('en')
    critical=('Домен и его вариант с www идут напрямую. Для gosuslugi.ru также исключается gu-st.ru — он нужен для загрузки интерфейса Госуслуг. Другие поддомены добавляйте отдельно. Изменения вступят в силу после переподключения VPN.',
    'На вкладке «Главная» выберите профиль и нажмите «Подключиться». При первом подключении iOS попросит разрешить VPN-конфигурацию — подтвердите системный запрос.',
    'APL не продаёт и не предоставляет прокси-серверы. Без действующих данных подключиться не получится.',
    'После первоначальной настройки режим меняется здесь, в APL. Системные автоматизации переделывать не нужно.')
    for c in NEW:
        v=pairs(c)
        for key in critical:
            assert key in v and len(v[key])>30,(c,key)
        assert 'gu-st.ru' in v[critical[0]] and 'gosuslugi.ru' in v[critical[0]]
