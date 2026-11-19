from pathlib import Path
import sys,plistlib
import pytest
IOS=Path(__file__).resolve().parents[1]/'mobile/ios'
sys.path.insert(0,str(IOS/'Tools'))
from audit_ios_privacy_bundle import audit

def test_explicit_ad_startup_only_after_disclosure_and_enabled():
    app=(IOS/'App/ArvectumProxyLauncherApp.swift').read_text()
    assert '    init()' not in app
    assert 'guard privacyDisclosureAccepted, shouldInitializeAds, !adsStartupCompleted' in app
    assert 'return IOSAdsConfig.isEnabled' in app
    assert app.count('YandexAds.initializeSDK(')==1
    assert 'if !shouldInitializeAds || adsStartupCompleted' in app
    assert 'ProgressView().onAppear { startAdsAfterDisclosure() }' in app
    view=(IOS/'App/NativeHomeAdView.swift').read_text()
    assert 'private lazy var loader = NativeAdLoader()' in view and 'fileprivate lazy var adView' in view

def test_disclosure_reopen_and_locale_binding():
    view=(IOS/'App/PrivacyDisclosureView.swift').read_text();settings=(IOS/'App/CompactSettingsView.swift').read_text()
    assert '@Binding var appLanguage: String' in view and 'Picker(selection: $appLanguage)' in view
    assert 'table: "PrivacyDetails", language: appLanguage' in view
    assert 'reviewOnly ? "privacy.closeReview" : "privacy.continue"' in view
    assert 'PrivacyDisclosureView(appLanguage:$appLanguage,reviewOnly:true)' in settings
    assert 'privacyDisclosureAccepted' not in settings
    assert {p.parent.name for p in (IOS/'Resources').glob('*.lproj/PrivacyDetails.strings')}=={'ru.lproj','en.lproj'}

def test_manifest_audit_distinguishes_vendor_declarations_from_app(tmp_path):
    app=tmp_path/'app';app.mkdir();(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'ru.arvectum.proxylauncher.ios','CFBundleExecutable':'APL'}));(app/'APL').write_bytes(b'test')
    def manifest(rel,tracking=False,types=()):
        p=app/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(plistlib.dumps({'NSPrivacyTracking':tracking,'NSPrivacyCollectedDataTypes':[{'NSPrivacyCollectedDataType':t} for t in types]}))
    manifest('PrivacyInfo.xcprivacy');manifest('PlugIns/Arvectum Packet Tunnel.appex/PrivacyInfo.xcprivacy');(app/'PlugIns/Arvectum Packet Tunnel.appex/Arvectum Packet Tunnel').write_bytes(b'extension')
    manifest('Frameworks/YandexMobileAds.framework/PrivacyInfo.xcprivacy',types=['NSPrivacyCollectedDataTypeDeviceID']);(app/'Frameworks/YandexMobileAds.framework/YandexMobileAds').write_bytes(b'sdk')
    manifest('AppMetrica_AppMetricaAdSupport.bundle/PrivacyInfo.xcprivacy',True,['NSPrivacyCollectedDataTypeDeviceID'])
    result=audit(app);assert result['manifest_count']==4 and result['app_declares_no_collection'] and result['ads_declares_collection'] and result['appmetrica_adsupport_tracking']
    assert result['release_authorized'] is False and result['runtime_authorized'] is False
    (app/'embedded.mobileprovision').write_bytes(b'test')
    with pytest.raises(ValueError):audit(app)
