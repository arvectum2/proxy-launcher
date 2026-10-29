"""Tier-2 Urdu, Bengali, Punjabi (Gurmukhi), Tamil, Telugu localization contracts."""
import ast,json,re,xml.etree.ElementTree as ET
from pathlib import Path
R=Path(__file__).resolve().parents[1]
LANGS=('ur','bn','pa','ta','te')
PAT=re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')
FMT=re.compile(r'%(?:\d+\$)?(?:@|s|d|f)')

def ios(code):
    p=R/f'mobile/ios/Resources/{code}.lproj/Localizable.strings'
    return {m.group(1):m.group(2) for line in p.read_text().splitlines() if (m:=PAT.fullmatch(line))}

def android(code):
    p=R/f'mobile/android/app/src/main/res/values-{"b+pa+Guru" if code == "pa" else code}/strings.xml'
    return {x.attrib['name']:x.text or '' for x in ET.parse(p).getroot()}

def desktop():
    astnode=ast.parse((R/'desktop_i18n.py').read_text())
    node=next(x.value for x in astnode.body if isinstance(x,ast.Assign) and any(getattr(t,'id','')=='CATALOGS' for t in x.targets))
    return ast.literal_eval(node)

def test_registry_and_rtl():
    langs=json.loads((R/'localization/apl-locales.json').read_text())['languages']
    assert len(langs)==26 and langs[-5:]==list(LANGS)
    src=(R/'mobile/ios/App/AppLocalization.swift').read_text()
    assert all(f'case {code}' in src for code in LANGS)
    for name in ('اردو','বাংলা','ਪੰਜਾਬੀ','தமிழ்','తెలుగు'):
        assert name in src
    assert '["fa", "ar", "ur"].contains(AppL10n.effectiveLanguage)' in (R/'mobile/ios/App/ArvectumProxyLauncherApp.swift').read_text()
    assert 'LANGUAGE in ("fa", "ar", "ur")' in (R/'proxy_gui.py').read_text()
    assert 'android:supportsRtl="true"' in (R/'mobile/android/app/src/main/AndroidManifest.xml').read_text()
    src=(R/'mobile/android/app/src/main/java/ru/arvectum/proxylauncher/MainActivity.kt').read_text()
    for n in ('hostField.textDirection = View.TEXT_DIRECTION_LTR', 'portField.textDirection = View.TEXT_DIRECTION_LTR'):
        assert n in src

def test_all_five_source_catalogs_and_sensitive_ui_contracts():
    base=ios('en');a0=android('en');D=desktop()
    for lang in LANGS:
        i=ios(lang);a=android(lang);d=D[lang]
        assert len(i)==len(base)==155 and set(i)==set(base)
        assert len(a)==len(a0)==104 and set(a)==set(a0)
        assert len(d)==len(D['ru'])==193 and set(d)==set(D['ru'])
        for k,v in i.items():assert v.strip() and FMT.findall(v)==FMT.findall(base[k]),(lang,k)
        for k,v in a.items():assert v.strip() and FMT.findall(v)==FMT.findall(a0[k]),(lang,k)
        assert all(v.strip() for v in d.values())
        assert a['app_title']=='Arvectum Proxy Launcher'
        warning=next(v for k,v in d.items() if k.startswith('Предыдущий сеанс завершился некорректно. Нажмите'))
        assert d['Восстановить сеть'] in warning,lang
        tech=' '.join(i.values())
        for token in ('SOCKS5','Network Extension','Packet Tunnel','gu-st.ru'):
            assert token in tech,(lang,token)
        for k,v in d.items():assert FMT.findall(v)==FMT.findall(D['ru'][k]),(lang,k)
