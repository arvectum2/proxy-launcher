"""Source contracts for 15 former Soviet republics and 64 APL iOS UI languages.

App Store Connect only exposes 50 ASO locales; these 11 new UI languages
must NOT be inserted as imaginary Apple App Store metadata locale codes.
"""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / 'mobile/ios'
RES = IOS / 'Resources'
sys.path.insert(0, str(ROOT / 'scripts'))
from ios_020_locale_audit import read_strings, format_error

COUNTRY_LANGUAGE = {
    'Russia': 'ru', 'Belarus': 'be', 'Ukraine': 'uk', 'Moldova': 'ro',
    'Estonia': 'et', 'Latvia': 'lv', 'Lithuania': 'lt',
    'Georgia': 'ka', 'Armenia': 'hy', 'Azerbaijan': 'az',
    'Kazakhstan': 'kk', 'Uzbekistan': 'uz', 'Turkmenistan': 'tk',
    'Kyrgyzstan': 'ky', 'Tajikistan': 'tg',
}
NEW = {'be','et','lv','lt','ka','hy','az','kk','tk','ky','tg'}
TABLES = ('Localizable', 'ProfileManagement','ProxyImport','SmartExclusions','QuickActions')
TECH = ('APL', 'iOS', 'VPN', 'SOCKS5', 'HTTP', 'HTTPS', 'Network Extension',
        'Packet Tunnel', 'Keychain', 'host:port', 'http://', 'https://',
        'socks5://', 'gosuslugi.ru', 'gu-st.ru', 'TXT/CSV/XML')


def test_all_15_former_republics_have_native_primary_language_in_64_ui_catalogs():
    manifest=json.loads((IOS/'ios-locales.json').read_text())['languages']
    assert len(COUNTRY_LANGUAGE)==15 and len(NEW)==11
    assert len(manifest)==len(set(manifest))==64
    assert set(COUNTRY_LANGUAGE.values()).issubset(manifest)
    assert set(manifest)=={d.name.removesuffix('.lproj') for d in RES.glob('*.lproj')}
    assert len(list(RES.glob('*.lproj/*.strings')))==320
    for lang in NEW:
        folder=RES/f'{lang}.lproj'
        for table in TABLES:
            baseline,_=read_strings(RES/'en.lproj'/f'{table}.strings')
            actual,duplicates=read_strings(folder/f'{table}.strings')
            assert not duplicates and set(actual)==set(baseline),(lang,table)
            assert all(v.strip() for v in actual.values()),(lang,table)
            assert all(format_error(k,v) is None for k,v in actual.items()),(lang,table)


def test_tech_identifiers_are_not_mangled_in_11_new_translations():
    for lang in NEW:
        for table in TABLES:
            base,_=read_strings(RES/'en.lproj'/f'{table}.strings')
            actual,_=read_strings(RES/f'{lang}.lproj'/f'{table}.strings')
            for key,translated in actual.items():
                english=base[key]
                for token in TECH:
                    if token in english:
                        assert token in translated,(lang,table,key[:65],token,translated[:90])
                if len(english)>55 and english.count(' ')>=7:
                    assert english.casefold().strip()!=translated.casefold().strip(),(lang,table,key[:60])


def test_script_picker_labels_and_ad_labels_cover_64_languages():
    # Script distinctness: do not claim English/Russian transliteration is the full localized UI.
    script={
        'be': (0x0400,0x052f), 'ka': (0x10a0,0x10ff),
        'hy': (0x0530,0x058f), 'kk': (0x0400,0x052f),
        'ky': (0x0400,0x052f), 'tg': (0x0400,0x052f),
    }
    for lang,(low,high) in script.items():
        collected=' '.join(value for file in (RES/f'{lang}.lproj').glob('*.strings')
                           for value in read_strings(file)[0].values())
        assert sum(low <= ord(c) <= high for c in collected)>=100,(lang,collected[:170])
    unique_letters={
        'be':'ўі', 'et':'õäöü', 'lv':'āēīūģķļņšž', 'lt':'ąčęėįšųūž',
        'ka':'აბგდევზთიკლმნოპჟრსტუფქღყშჩცძწჭხჯჰ',
        'hy':'աբգդեզէըթժիլխծկհձղճմյնշոչպջռսվտրցւփքօֆ',
        'az':'əğışçöü', 'kk':'әіңғүұқөһ', 'tk':'äňöşüýž',
        'ky':'ңөү', 'tg':'ғӣқӯҳҷ',
    }
    for lang,letters in unique_letters.items():
        collected=' '.join(value.casefold() for file in (RES/f'{lang}.lproj').glob('*.strings')
                           for value in read_strings(file)[0].values())
        assert sum(collected.count(c) for c in letters)>=5,(lang,'target script absent')
    source=(IOS/'App/AppLocalization.swift').read_text()
    ads=(IOS/'App/SettingsBannerView.swift').read_text()
    for lang in NEW:
        assert re.search(r'^    case '+lang+r'$',source,re.M),lang
        assert re.search(r'^        case \.'+lang+r': return "[^"]+"$',source,re.M),lang
        assert re.search(r'"'+lang+r'"\s*:\s*"[^"]+"',ads),lang
        assert '"'+lang+'"' in source,lang
    assert '64 fully populated APL iOS source languages' in source
    for variant in ('kk-latn','az-cyrl','tg-arab'):
        assert variant in source
    payload=json.loads((IOS/'ASO/localizations.json').read_text())
    assert payload['supportedLocaleCount']==len(payload['localizations'])==50
    assert not ({r['locale'] for r in payload['localizations']} & NEW)
    assert len(list((IOS/'ASO/screenshots').glob('*/*.jpg')))==100
