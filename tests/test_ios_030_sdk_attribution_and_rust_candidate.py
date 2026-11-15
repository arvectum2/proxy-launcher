import json
from pathlib import Path
IOS=Path(__file__).resolve().parents[1]/'mobile/ios'

def test_attribution_is_present_in_about_and_all_offline_descriptions():
    view=(IOS/'App/CompactSettingsView.swift').read_text()
    assert 'settings.aboutSDKAttribution' in view and 'sheet(isPresented:$showAbout)' in view
    entries=json.loads((IOS/'ASO/localizations.json').read_text())['localizations']
    assert len(entries)==50
    for entry in entries:
        prefix='Создано с использованием ' if entry['locale']=='ru' else 'Developed with the use of '
        for sdk in ['Yandex Mobile Ads SDK','Yandex AppMetrica SDK']:
            assert prefix+sdk in view and prefix+sdk in entry['description']
            assert prefix+sdk in (IOS/'ASO/metadata'/entry['locale']/'description.txt').read_text()

def test_rust_alternative_is_isolated_and_does_not_replace_pinned_release():
    t=(IOS/'Tools/prepare_ios_rust_without_tproxy.py').read_text()
    assert 'cfg(not(target_os="ios"))' in t and 'cidr = { version = "=0.3.2"' in t
    assert 'tproxy-config v\' not in tree' in t and 'aarch64-apple-ios-sim' in t
    assert 'unexpected resolution change' in t and '--locked' in t and '--offline' in t
    assert 'release_authorized\':False' in t and 'Frameworks/' not in t
    b=(IOS/'Tools/build_product_unified_candidate_unsigned.sh').read_text()
    assert 'e81642cf494e218aeb3314289f235eeff8dff21dc8d72b8bd23ded8b41c0b852' in b
