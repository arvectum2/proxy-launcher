"""Native profile copy uses separate, auditable locale resources."""
import re
import json
import sys
import unicodedata
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from ios_020_locale_audit import read_strings,format_error
RES=ROOT/'mobile/ios/Resources'
APP=ROOT/'mobile/ios/App/NativePersistentProfilesView.swift'

def test_native_catalogs_match_actual_source_and_fallback():
    src=APP.read_text()
    pairs=set(re.findall(r'(?:tr|label)\("([^"\\]*)","([^"\\]*)"\)',src))
    shared=set(re.findall(r'case \("([^"\n]+)", "([^"\n]+)"\): return AppL10n.tr',src))
    remaining=pairs-shared
    en,duplicates=read_strings(RES/'en.lproj/NativeProfiles.strings')
    ru,_=read_strings(RES/'ru.lproj/NativeProfiles.strings')
    assert not duplicates
    assert en=={r:e for e,r in remaining}
    assert ru=={r:r for e,r in remaining}
    assert len(en)==85 and len(shared)==19
    assert 'AppL10n.tr(ru, table: "NativeProfiles", language: language)' in src
    paths=list(RES.glob('*.lproj/NativeProfiles.strings'))
    assert len(paths)==64
    complete=set()
    for p in paths:
        data,duplicates=read_strings(p)
        locale=p.parent.name[:-6]
        assert not duplicates and set(data)<=set(en)
        assert data.get('VPN-профили')
        assert all(v.strip() and not format_error(k,v) for k,v in data.items())
        if set(data)==set(en):
            complete.add(locale)
            for key,english in en.items():
                for token in ('VPN','IP','IPv4','ID'):
                    if token in english:
                        assert token in data[key], (locale,key,token)
    assert complete==set(json.loads((ROOT/'mobile/ios/ios-locales.json').read_text())['languages'])
    assert len(complete)==64


def test_native_non_latin_catalogs_do_not_mix_unrelated_scripts():
    scripts={
        'am':{'ETHIOPIC'},'ar':{'ARABIC'},'fa':{'ARABIC'},'ur':{'ARABIC'},
        'he':{'HEBREW'},'hy':{'ARMENIAN'},'ka':{'GEORGIAN'},'el':{'GREEK'},
        'bn':{'BENGALI'},'gu':{'GUJARATI'},'hi':{'DEVANAGARI'},'mr':{'DEVANAGARI'},
        'kn':{'KANNADA'},'ml':{'MALAYALAM'},'or':{'ORIYA'},'pa':{'GURMUKHI'},
        'ta':{'TAMIL'},'te':{'TELUGU'},'th':{'THAI'},
        'be':{'CYRILLIC'},'bg':{'CYRILLIC'},'kk':{'CYRILLIC'},'ky':{'CYRILLIC'},
        'tg':{'CYRILLIC'},'uk':{'CYRILLIC'},'ru':{'CYRILLIC'},'sr':{'CYRILLIC'},
        'ko':{'HANGUL'},'zh-Hans':{'CJK'},'zh-Hant':{'CJK'},
        'ja':{'CJK','HIRAGANA','KATAKANA','KATAKANA-HIRAGANA'},
    }
    for locale,expected in scripts.items():
        data,_=read_strings(RES/(locale+'.lproj')/'NativeProfiles.strings')
        for key,value in data.items():
            letters={unicodedata.name(c,'').split(' ')[0] for c in value
                     if unicodedata.category(c).startswith('L')}
            assert letters & expected,(locale,key,'no localized script')
            assert letters <= expected | {'LATIN'},(locale,key,letters-expected-{'LATIN'})
