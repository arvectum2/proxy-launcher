"""Native ChatGPT-authored Tier-3 terminology and safety-copy drafts; not release locales."""
import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
TARGETS={'ha','am','sv','da','fi','nb','bg','sr','hr','ca'}
TOKENS=('gosuslugi.ru','gu-st.ru','VPN')
def load(name):return json.loads((ROOT/'localization/drafts'/name).read_text())

def test_all_tier3_terminology_drafts_are_complete():
    terms=load('tier3-glossary.json');existing=json.loads((ROOT/'localization/editorial-glossary.json').read_text())
    assert terms['status']=='editorial_draft_not_product_catalog'
    assert set(terms['languages'])==TARGETS
    for lang,d in terms['languages'].items():
        assert set(d)==set(existing['terms']) and len(d)==28
        assert all(isinstance(v,str) and v.strip() for v in d.values())
        assert d['Прокси']!=d['Пароль'] and d['Подключено']!=d['Отключено']
    assert re.search('[\u1200-\u137f]',terms['languages']['am']['Прокси'])
    assert re.search('[\u0400-\u04ff]',terms['languages']['sr']['Прокси'])

def test_tier3_ios_critical_editorial_draft_structure_and_literals():
    doc=load('tier3-critical-ios.json');d=doc['ios_en_source_strings']
    assert doc['status']=='reviewed_draft_not_product_catalog' and set(d)==TARGETS
    first=next(iter(d.values()))
    assert len(first)==16
    source_keys=set(first)
    for lang,entries in d.items():
        assert set(entries)==source_keys
        assert all(isinstance(v,str) and v.strip() for v in entries.values())
        for en,tr in entries.items():
            if 'gosuslugi.ru' in en:
                assert all(tok in tr for tok in TOKENS),(lang,tr)
            for tok in ('SOCKS5','HTTPS','HTTP','APL','iOS'):
                if tok in en:assert tok in tr,(lang,tok)
            if 'App Opened/Closed trigger' in en:assert 'Apple' in tr
        assert any('host:port' in x for x in entries.values())
    assert re.search('[\u1200-\u137f]', ' '.join(d['am'].values()))
    assert re.search('[\u0400-\u04ff]', ' '.join(d['sr'].values()))

def test_drafts_not_in_active_language_catalog_or_picker():
    active=json.loads((ROOT/'localization/apl-locales.json').read_text())
    assert not TARGETS.intersection(active['languages'])
    assert len(active['languages'])==40
    for lang in TARGETS:assert not (ROOT/f'mobile/ios/Resources/{lang}.lproj').exists()
