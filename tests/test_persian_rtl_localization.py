"""Persian resource and right-to-left display integration."""
import ast
import re
import xml.etree.ElementTree as ET
from pathlib import Path

R = Path(__file__).resolve().parents[1]


def test_ios_persian_complete_and_rtl():
    source = (R / 'mobile/ios/Resources/fa.lproj/Localizable.strings').read_text()
    assert len(re.findall(r'^".*" = ".*";$', source, re.M)) == 155
    for token in ('پروکسی', 'پورت', 'Network Extension', 'Packet Tunnel', 'SOCKS5', 'gu-st.ru'):
        assert token in source
    localization = (R / 'mobile/ios/App/AppLocalization.swift').read_text()
    assert 'case fa' in localization and 'return "فارسی"' in localization
    app = (R / 'mobile/ios/App/ArvectumProxyLauncherApp.swift').read_text()
    assert '["fa", "ar", "ur"].contains(AppL10n.effectiveLanguage) ? .rightToLeft : .leftToRight' in app
    assert 'fa.lproj' in (R / 'mobile/ios/ArvectumProxyLauncherIOS.xcodeproj/project.pbxproj').read_text()


def test_android_persian_complete_and_rtl():
    base = R / 'mobile/android/app/src/main/res'
    a = ET.parse(base / 'values-fa/strings.xml').getroot()
    b = ET.parse(base / 'values-en/strings.xml').getroot()
    assert len(a) == len(b) == 104
    assert [s.get('name') for s in a] == [s.get('name') for s in b]
    manifest = (R / 'mobile/android/app/src/main/AndroidManifest.xml').read_text()
    assert 'android:supportsRtl="true"' in manifest
    assert 'android:label="@string/app_title"' in manifest
    data = {x.get('name'):x.text for x in a}
    assert data['apl_port_90947'] == 'پورت'
    assert data['apl_proxy_a5677'] == 'پروکسی'
    assert '%1$d' in data['apl_latency_milliseconds']


def test_desktop_persian_complete_and_right_justified():
    src = (R / 'desktop_i18n.py').read_text()
    tree = ast.parse(src)
    node = next(a.value for a in tree.body if isinstance(a, ast.Assign) and any(isinstance(x, ast.Name) and x.id == 'CATALOGS' for x in a.targets))
    d = ast.literal_eval(node)
    assert len(d['fa']) == 193
    assert d['fa']['Порт'] == 'پورت'
    assert d['fa']['Восстановить сеть'] in next(v for k,v in d['fa'].items() if k.startswith('Предыдущий сеанс завершился некорректно. Нажмите «Восстановить сеть»'))
    source = (R / 'proxy_gui.py').read_text()
    assert 'root.option_add("*Label.justify", "right")' in source
