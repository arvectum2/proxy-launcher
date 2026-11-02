"""No one-line native TabView labels may overlap in the four-slot iPhone SE bar."""
from pathlib import Path
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from ios_020_locale_audit import read_strings

ROOT=Path(__file__).resolve().parents[1]
IOS=ROOT/'mobile/ios'
SWIFT=(IOS/'App/AppDestination.swift').read_text()
OVERRIDES={code:dict(re.findall(r'\.(home|profiles|activity|settings): "([^"]+)"',chunk))
           for code,chunk in re.findall(r'^        "([^"]+)": \[([^\]]+)\]',SWIFT,re.M)}


def test_all_64_iPhone_tab_labels_have_compact_meaningful_native_text():
    langs={p.name[:-6] for p in (IOS/'Resources').glob('*.lproj')}
    assert len(langs)==64
    keys={'home':'Главная','profiles':'Профили','activity':'Активность','settings':'Настройки'}
    assert 'if let short = Self.compactTabLabels[AppL10n.effectiveLanguage]?[self]' in SWIFT
    for lang in langs:
        normal,_=read_strings(IOS/'Resources'/f'{lang}.lproj'/'Localizable.strings')
        for destination,key in keys.items():
            actual=OVERRIDES.get(lang,{}).get(destination,normal[key])
            assert 0<len(actual)<=11,(lang,destination,actual)
            assert '\n' not in actual and '...' not in actual,(lang,destination,actual)
    # Human-reviewed regression cases; do not silently revert to verbose MT.
    assert OVERRIDES['tg']=={'home':'Асосӣ','profiles':'Профилҳо',
                              'activity':'Фаъолият','settings':'Танзимот'}
    assert OVERRIDES['ka']['activity']=='აქტივობა'
    assert OVERRIDES['hy']['home']=='Գլխավոր'
    assert OVERRIDES['ar']['profiles']=='ملفاتي'


def test_theme_labels_and_controls_never_force_truncated_segments():
    # Native segmented controls cannot fit three arbitrarily long localized
    # strings in a 240pt width. Longer languages must use menu presentation.
    settings=(IOS/'App/CompactSettingsView.swift').read_text()
    assert 'AppearanceMode.allCases.contains(where: { $0.title.count > 9 })' in settings
    for code in ('be','et','lv','lt','ka','hy','az','kk','tk','ky','tg'):
        d,_=read_strings(IOS/'Resources'/f'{code}.lproj'/'Localizable.strings')
        labels,_=read_strings(IOS/'Resources'/f'{code}.lproj'/'ProfileManagement.strings')
        for key in ('Системная','Светлая','Тёмная','Первое подключение'):
            assert d[key].strip(),(code,key)
        for key in ('Язык','Тема'):
            assert labels[key].strip(),(code,key)
        for value in (d['Системная'],d['Светлая'],d['Тёмная']):
            assert '...' not in value and not value.endswith('.'),(code,value)
