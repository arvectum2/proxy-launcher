"""Preserve shipped Yandex banner and validate native UI editorial across 50 iOS locales."""
import json
import plistlib
import re
from pathlib import Path

IOS=Path(__file__).resolve().parents[1]/'mobile/ios'
CODES=json.loads((IOS/'ios-locales.json').read_text(encoding='utf-8'))['languages']
LINE=re.compile(r'^"((?:\\.|[^"\\])*)" = "((?:\\.|[^"\\])*)";$')


def catalog(lang):
    return dict(m.groups() for line in (IOS/'Resources'/f'{lang}.lproj/Localizable.strings').read_text(encoding='utf-8').splitlines() if (m:=LINE.fullmatch(line)))


def test_shipped_banner_wiring_is_restored_in_ios_release_source():
    project=(IOS/'project.yml').read_text(encoding='utf-8')
    banner=(IOS/'App/SettingsBannerView.swift').read_text(encoding='utf-8')
    home=(IOS/'App/ContentView.swift').read_text(encoding='utf-8')
    pbx=(IOS/'ArvectumProxyLauncherIOS.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
    assert 'https://github.com/yandexmobile/yandex-ads-sdk-ios' in project
    assert 'package: YandexMobileAds' in project
    assert 'OTHER_LDFLAGS: "$(inherited) -ObjC"' in project
    assert 'YandexMobileAds in Frameworks' in pbx
    assert 'SettingsBannerView.swift in Sources' in pbx
    assert 'R-M-20288304-1' in banner
    assert 'static let isEnabled = true' in banner
    assert 'activeBannerUnitID = productionBannerUnitID' in banner
    assert 'activeBannerUnitID = demoBannerUnitID' in banner
    assert 'TabView(selection: $destination)' in home
    layout=home.split('private var homeScreen: some View {',1)[1].split('private var dashboardCardMaxHeight',1)[0]
    assert layout.index('homeMeasured("header")') < layout.index('SettingsBannerView(')
    assert layout.index('SettingsBannerView(') < layout.index('homeConnectControl')
    assert '.safeAreaInset(edge: .bottom, spacing: 0)' not in home
    assert 'SettingsBannerView(' in home
    assert 'size: .inline(width: max(1, adWidth), maxHeight: maxAdHeight)' in banner
    assert '.frame(minHeight: 80, maxHeight: maxAdHeight)' in banner
    assert '.onAdLoad' in banner and '.onAdFailure' in banner
    assert '.onAdImpression' in banner
    plist=plistlib.loads((IOS/'Config/App-Info.plist').read_bytes())
    ids=[r['SKAdNetworkIdentifier'] for r in plist['SKAdNetworkItems']]
    assert len(ids)>=200 and len(ids)==len(set(ids))
    assert 'zq492l623r.skadnetwork' in ids
    assert '.accessibilityHidden(!loaded)' in banner


def test_ad_disclosure_label_is_present_in_every_ios_language():
    banner=(IOS/'App/SettingsBannerView.swift').read_text(encoding='utf-8')
    segment=banner.split('static let labels: [String: String] = [',1)[1].split('\n    ]',1)[0]
    found=dict(re.findall(r'^\s*"([^\"]+)": "([^\"]+)",$',segment,re.M))
    assert len(found)==len(CODES)==50
    assert set(found)==set(CODES)
    assert all(value.strip() and len(value.strip())<35 for value in found.values())
    assert found['ru']=='Реклама' and found['en']=='Ad'
    assert found['he']=='פרסומת' and found['ar']=='إعلان'
    assert 'IOSAdsConfig.localizedAdLabel' in banner


def test_privacy_onboarding_statements_are_naturally_localized_and_consistent():
    for lang in CODES:
        strings=catalog(lang)
        assert len(strings)==155
        assert strings['Без аналитики и рекламы'].strip()
        assert strings['В этой версии нет рекламных SDK, аналитики, трекинга, регистрации или облачного backend.'].strip()
        assert strings['Без аналитики и рекламы'] != strings['В этой версии нет рекламных SDK, аналитики, трекинга, регистрации или облачного backend.']
    assert catalog('en')['Без аналитики и рекламы']=='No account required'
    assert 'Connection details remain on this device' in catalog('en')['В этой версии нет рекламных SDK, аналитики, трекинга, регистрации или облачного backend.']
    assert catalog('pl')['Сохранить']=='Zapisz'
    assert catalog('nl')['Сохранить']=='Opslaan'
    assert catalog('id')['Сохранить']=='Simpan'
    assert catalog('vi')['Сохранить']=='Lưu'
    assert catalog('ms')['Сохранить']=='Simpan'
    assert catalog('tr')['Сохранить']=='Kaydet'
    assert catalog('hi')['Сохранить']=='सहेजें'
    assert catalog('ar')['Сохранить']=='حفظ'
