"""Apple-50 App Store metadata vs iOS-64 in-app locale coverage for APL 0.2.0.

Offline source contract only; never accesses App Store Connect or device secrets.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / 'mobile/ios'
RES = IOS / 'Resources'
ASO = IOS / 'ASO'
sys.path.insert(0, str(ROOT / 'scripts'))
from ios_020_locale_audit import read_strings

NEW = {'or': 'or-IN', 'sl': 'sl-SI', 'uk': 'uk'}
TABLES = {'Localizable': 155, 'ProfileManagement': 101,
          'ProxyImport': 40, 'SmartExclusions': 51, 'QuickActions': 3}


def test_53_ui_languages_all_have_five_complete_catalogs():
    manifest = json.loads((IOS / 'ios-locales.json').read_text())
    languages = manifest['languages']
    assert len(languages) == len(set(languages)) == 64
    assert set(languages) == {p.name[:-6] for p in RES.glob('*.lproj')}
    assert len(list(RES.glob('*.lproj/*.strings'))) == 64 * len(TABLES) == 320
    for code in NEW:
        folder = RES / f'{code}.lproj'
        for table, count in TABLES.items():
            actual, dupes = read_strings(folder / f'{table}.strings')
            english, _ = read_strings(RES / 'en.lproj' / f'{table}.strings')
            assert not dupes and len(actual) == count and set(actual) == set(english), (code, table)
        primary, _ = read_strings(folder / 'Localizable.strings')
        imp, _ = read_strings(folder / 'ProxyImport.strings')
        assert primary['Подключиться'] != primary['Отключить']
        assert 'gosuslugi.ru' in primary['Домен и его вариант с www идут напрямую. Для gosuslugi.ru также исключается gu-st.ru — он нужен для загрузки интерфейса Госуслуг. Другие поддомены добавляйте отдельно. Изменения вступят в силу после переподключения VPN.']
        assert all(token in imp['Поддерживаются ссылки http://, https:// и socks5://']
                   for token in ('http://', 'https://', 'socks5://'))
    odia = ' '.join(read_strings(p)[0].get('Исключения', '') for p in (RES / 'or.lproj').glob('*.strings'))
    assert any('\u0b00' <= c <= '\u0b7f' for c in odia), 'Odia label must be in Odia script'


def test_all_50_apple_metadata_locales_and_new_region_mapping_are_offline_ready():
    data = json.loads((ASO / 'localizations.json').read_text())
    entries = data['localizations']
    assert data['state'] == 'editorial_source_ready_not_uploaded'
    assert data['supportedLocaleCount'] == len(entries) == 50
    assert len({r['locale'] for r in entries}) == 50
    assert len({r['iosLanguage'] for r in entries}) == 45
    mapping = {r['locale']: r['iosLanguage'] for r in entries}
    for language, apple_locale in NEW.items():
        assert mapping[apple_locale] == language
        folder = ASO / 'screenshots' / apple_locale
        photos = [folder / '01-first-connection.jpg', folder / '02-local-privacy.jpg']
        assert all(p.is_file() and p.stat().st_size > 15000 for p in photos)
        assert photos[0].read_bytes() != photos[1].read_bytes()
    assert len(list(ASO.glob('screenshots/*/*.jpg'))) == 100
