"""Czech, Slovak, Greek, Hebrew Core Tier-2 source and RTL contracts."""
import ast,json,re,xml.etree.ElementTree as ET
from pathlib import Path
R=Path(__file__).resolve().parents[1]
LANGS=('cs','sk','el','he')
PAT=re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')
FMT=re.compile(r'%(?:\d+\$)?(?:@|s|d|f)')
def ios(c):
    p=R/f'mobile/ios/Resources/{c}.lproj/Localizable.strings'
    return {m.group(1):m.group(2) for line in p.read_text().splitlines() if (m:=PAT.fullmatch(line))}
def android(c):
    p=R/f'mobile/android/app/src/main/res/values-{"iw" if c=="he" else c}/strings.xml'
    return {x.attrib['name']:x.text or '' for x in ET.parse(p).getroot()}
def desktop():
    root=ast.parse((R/'desktop_i18n.py').read_text())
    n=next(x.value for x in root.body if isinstance(x,ast.Assign) and any(getattr(t,'id','')=='CATALOGS' for t in x.targets))
    return ast.literal_eval(n)

def test_complete_catalogs_formats_and_network_safety():
    base=ios('en');a0=android('cs');D=desktop()
    for c in LANGS:
        i=ios(c);a=android(c);d=D[c]
        assert len(i)==len(base)==155 and set(i)==set(base)
        assert len(a)==len(a0)==104 and set(a)==set(a0)
        assert len(d)==len(D['en'])==193 and set(d)==set(D['en'])
        assert all(v.strip() and FMT.findall(v)==FMT.findall(base[k]) for k,v in i.items())
        assert all(v.strip() and FMT.findall(v)==FMT.findall(a0[k]) for k,v in a.items())
        assert all(v.strip() and FMT.findall(v)==FMT.findall(D['en'][k]) for k,v in d.items())
        assert a['app_title']=='Arvectum Proxy Launcher'
        rec=next(v for k,v in d.items() if k.startswith('Предыдущий сеанс завершился некорректно. Нажмите'))
        diag=next(v for k,v in d.items() if k.startswith('предыдущий сеанс. Автоматический сброс'))
        assert d['Восстановить сеть'] in rec and d['Диагностика'] in diag
        assert all(tok in ' '.join(i.values()) for tok in ('SOCKS5','HTTPS','Network Extension','Packet Tunnel','gu-st.ru'))

def test_core40_registry_and_hebrew_rtl():
    d=json.loads((R/'localization/apl-locales.json').read_text())
    assert len(d['languages'])==40 and d['languages'][-4:]==list(LANGS)
    src=(R/'mobile/ios/App/AppLocalization.swift').read_text()
    for c,label in zip(LANGS,('Čeština','Slovenčina','Ελληνικά','עברית')):
        assert f'case {c}' in src and label in src
    assert '["fa", "ar", "ur", "he"].contains(AppL10n.effectiveLanguage)' in (R/'mobile/ios/App/ArvectumProxyLauncherApp.swift').read_text()
    assert 'LANGUAGE in ("fa", "ar", "ur", "he")' in (R/'proxy_gui.py').read_text()
    assert 'android:supportsRtl="true"' in (R/'mobile/android/app/src/main/AndroidManifest.xml').read_text()
    kotlin=(R/'mobile/android/app/src/main/java/ru/arvectum/proxylauncher/MainActivity.kt').read_text()
    for tok in ('hostField.textDirection = View.TEXT_DIRECTION_LTR','portField.textDirection = View.TEXT_DIRECTION_LTR'):
        assert tok in kotlin
