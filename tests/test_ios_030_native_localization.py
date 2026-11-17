"""Native profile copy uses separate, auditable locale resources."""
import re
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from ios_020_locale_audit import read_strings,format_error
RES=ROOT/'mobile/ios/Resources'
APP=ROOT/'mobile/ios/App/NativePersistentProfilesView.swift'
FULL={'en','ru','es','de','fr','uk','pt-BR','zh-Hans'}

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
        if set(data)==set(en):complete.add(locale)
    assert FULL<=complete
