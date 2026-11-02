"""Meaning-sensitive 11-language QA: guards against previous MT hallucinations.

This is objective contract validation, not human native-speaker editorial approval.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'mobile/ios/Resources'
sys.path.insert(0, str(ROOT / 'scripts'))
from ios_020_locale_audit import read_strings, format_error

NEW = ('be','et','lv','lt','ka','hy','az','kk','tk','ky','tg')
TABLES=('Localizable','ProfileManagement','ProxyImport','SmartExclusions','QuickActions')
SCANNED_SHORT = ('Авто','Порт','Версия','Шаг','Журнал','Назад','Главная','Тема','Импорт','Режим','Копия','Хост','Русский')
EXPECTED_SAVES = {
    'be':'Захаваць', 'et':'Salvesta', 'lv':'Saglabāt', 'lt':'Išsaugoti',
    'ka':'შენახვა', 'hy':'Պահպանել', 'az':'Yadda saxla', 'kk':'Сақтау',
    'tk':'Sakla', 'ky':'Сактоо', 'tg':'Захира кардан',
}


def get(code,table):
    d,dupes=read_strings(RES/f'{code}.lproj'/f'{table}.strings')
    assert not dupes
    return d


def test_no_short_label_hallucinations_or_english_save_in_11_languages():
    for lang in NEW:
        tables={name:get(lang,name) for name in TABLES}
        assert tables['Localizable']['Сохранить']==EXPECTED_SAVES[lang],lang
        for table in TABLES:
            for key in SCANNED_SHORT:
                value=tables[table].get(key)
                if value is None:continue
                assert len(value)<72,(lang,table,key,value[:90])
                assert '00000' not in value and '1000 км' not in value,(lang,table,key)
                assert ' Save' not in value and ' Next' not in value,(lang,table,key)
        for word in ('Save','Кыргызстандын аймагында сейрек','Тахассус','դիպլոմ','км-ге жуық'):
            for table in TABLES:
                for key,value in tables[table].items():
                    if key in SCANNED_SHORT or key.startswith('Выкл. — остаёмся на резервном'):
                        assert word not in value,(lang,table,key,word)


def test_no_mangled_numeric_markers_and_end_user_routing_safety_in_11_locales():
    for lang in NEW:
        local=get(lang,'Localizable')
        profiles=get(lang,'ProfileManagement')
        import_copy=get(lang,'ProxyImport')
        rules=get(lang,'SmartExclusions')
        for name,table in TABLES_AS_ITEMS(lang):
            for key,value in table.items():
                assert not format_error(key,value),(lang,name,key)
        # Direct vs VPN route exceptions must be discussed explicitly.
        assert 'VPN' in rules['Обход VPN — только для разрешённых доменов.']
        assert 'VPN' in rules['VPN обходят только добавленные вручную или подтверждённые домены. Для применения сохраните изменения и переподключитесь.']
        assert 'VPN' in profiles['Существующие профили не перезаписываются. Совпадающие пропускаются. Перед восстановлением отключите VPN.']
        assert 'VPN' in profiles['Для удаления сначала отключите VPN.']
        assert 'VPN' in local['APL выключен, устройство работает напрямую. Открыли выбранное приложение — APL временно включился. Вышли — выключился обратно.'] or 'APL' in local['APL выключен, устройство работает напрямую. Открыли выбранное приложение — APL временно включился. Вышли — выключился обратно.']
        assert len(profiles['Выкл. — остаёмся на резервном без лишних переключений.'])<200
        assert len(profiles['Не все профили удалены:'])<110
        assert not (lang=='tg' and 'Тахассус' in ' '.join(profiles.values()))
        assert import_copy['Проверить']!=profiles['Проверить']


def TABLES_AS_ITEMS(lang):
    return [(name,get(lang,name)) for name in TABLES]


def test_cyrillic_is_not_accidentally_used_in_non_cyrillic_locales():
    for lang in ('ka','hy','et','lv','lt','az','tk'):
        for table in TABLES:
            catalog=get(lang,table)
            for key,value in catalog.items():
                assert not any('\u0400'<=x<='\u052f' for x in value), (lang,table,key,value[:80])
