"""Standalone source parity checks for APL Core 12 + new Persian language set."""
import ast
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / 'localization/apl-locales.json').read_text())
LANGS = MANIFEST['languages']
ANDROID = {
    'en': 'values-en', 'ru': 'values', 'es': 'values-es', 'fr': 'values-fr',
    'de': 'values-de', 'it': 'values-it', 'pt-BR': 'values-pt-rBR',
    'pt-PT': 'values-pt-rPT', 'ja': 'values-ja', 'ko': 'values-ko',
    'zh-Hans': 'values-b+zh+Hans', 'zh-Hant': 'values-b+zh+Hant', 'fa': 'values-fa', 'nl': 'values-nl', 'id': 'values-in', 'tr': 'values-tr', 'hi': 'values-hi', 'ar': 'values-ar', 'vi': 'values-vi', 'pl': 'values-pl', 'th': 'values-th', 'ur': 'values-ur', 'bn': 'values-bn', 'pa': 'values-b+pa+Guru', 'ta': 'values-ta', 'te': 'values-te', 'mr': 'values-mr', 'gu': 'values-gu', 'kn': 'values-kn', 'ml': 'values-ml', 'uz': 'values-b+uz+Latn', 'ms': 'values-ms', 'fil': 'values-fil', 'sw': 'values-sw', 'ro': 'values-ro', 'hu': 'values-hu',
}
STRING = re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')
FORMAT = re.compile(r'%(?:\d+\$)?(?:@|s|d|f)')


def ios_catalog(code):
    path = ROOT / f'mobile/ios/Resources/{code}.lproj/Localizable.strings'
    assert path.is_file(), path
    pairs = [STRING.fullmatch(line) for line in path.read_text().splitlines()
             if line and not line.startswith('/*')]
    assert all(pairs), f'Invalid Apple .strings line in {path}'
    catalog = {p.group(1): p.group(2) for p in pairs}
    assert len(pairs) == len(catalog)
    return catalog


def android_catalog(code):
    path = ROOT / 'mobile/android/app/src/main/res' / ANDROID[code] / 'strings.xml'
    assert path.is_file(), path
    entries = ET.parse(path).getroot()
    catalog = {e.attrib['name']: (e.text or '') for e in entries if e.tag == 'string'}
    assert len(catalog) == len(list(entries)), f'Duplicate resource in {path}'
    return catalog


def test_core_baseline_languages_and_registry():
    assert len(LANGS) == len(set(LANGS)) == 36
    assert LANGS == ['en', 'ru', 'es', 'fr', 'de', 'it', 'pt-BR', 'pt-PT',
                     'ja', 'ko', 'zh-Hans', 'zh-Hant', 'fa', 'nl', 'id', 'tr', 'hi', 'ar', 'vi', 'pl', 'th', 'ur', 'bn', 'pa', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'uz', 'ms', 'fil', 'sw', 'ro', 'hu']
    assert MANIFEST['stage'] == 'core36_editorial_source'
    assert MANIFEST['fallback'] == 'en'
    assert MANIFEST['appStoreConnectModified'] is False


def test_ios_catalogs_have_exact_same_keys_and_formats():
    reference = ios_catalog('en')
    assert len(reference) >= 155
    for code in LANGS:
        catalog = ios_catalog(code)
        assert set(catalog) == set(reference), (code, set(reference) ^ set(catalog))
        for key, text in catalog.items():
            assert text.strip(), (code, key)
            assert FORMAT.findall(text) == FORMAT.findall(reference[key]), (code, key)
            assert '⟦APLSEP⟧' not in text
        assert catalog['Подключиться'] and catalog['Настройки']


def test_app_language_picker_lists_all_core_languages():
    source = (ROOT / 'mobile/ios/App/AppLocalization.swift').read_text()
    assert 'case system' in source
    for code in LANGS:
        if '-' in code or code == 'id':
            assert f'= "{code}"' in source, code
        else:
            assert re.search(r'\bcase\s+' + code + r'\b', source), code
    assert 'Bundle.main.preferredLocalizations' in source
    assert 'AppL10n.systemLanguage' in source


def test_android_catalogs_have_exact_same_keys_and_formats():
    reference = android_catalog('ru')
    assert len(reference) >= 100
    for code in LANGS:
        catalog = android_catalog(code)
        assert set(catalog) == set(reference), (code, set(reference) ^ set(catalog))
        assert all(value.strip() for value in catalog.values()), code
        for key, text in catalog.items():
            assert FORMAT.findall(text) == FORMAT.findall(reference[key]), (code, key)
        assert 'site_exclusions_help' in catalog
        if code not in ('ru', 'en'):
            assert catalog['site_exclusions_help'] != android_catalog('en')['site_exclusions_help']


def test_desktop_embedded_catalogs_have_core_parity():
    source = (ROOT / 'desktop_i18n.py').read_text()
    ast.parse(source)
    context = {'__name__': 'desktop_i18n_test'}
    exec(compile(source, 'desktop_i18n.py', 'exec'), context)
    catalogs = context['CATALOGS']
    assert set(catalogs) == set(LANGS)
    reference = catalogs['ru']
    assert len(reference) >= 140
    for code in LANGS:
        assert set(catalogs[code]) == set(reference)
        assert all(value.strip() for value in catalogs[code].values()), code
        for key, val in catalogs[code].items():
            assert FORMAT.findall(val) == FORMAT.findall(key), (code, key)
    assert context['normalize']('zh-HK') == 'zh-Hant'
    assert context['normalize']('pt-BR') == 'pt-BR'
    assert context['normalize']('fr-FR') == 'fr'
    assert context['normalize']('und') is None
    assert catalogs['en']['Журнал'] == 'Log'


def test_existing_private_network_rules_not_retranslated():
    source = (ROOT / 'mobile/android/app/src/main/java/ru/arvectum/proxylauncher/MainActivity.kt').read_text()
    # These are backend-protocol and diagnostic clean-up anchors, not UI labels.
    assert '.startsWith("Подключено")' in source
    assert '.replace(". Создаём VPN…", "")' in source
    assert 'getString(R.string.apl_exclusions_saved_count, normalized.size)' in source
    desktop = (ROOT / 'proxy_gui.py').read_text()
    # Cyrillic keyboard keysyms are input protocol identifiers, not UI copy.
    assert 'event.keysym in ("v", "V", "м", "М")' in desktop
    assert 'event.keysym in ("v", "V", tr(' not in desktop
