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


def test_new_rust_archive_is_opt_in_and_old_fixtures_stay_default(tmp_path):
    import sys
    sys.path.insert(0,str(IOS/'Tools'))
    import unified_synthetic_fixture as f
    import unified_split_route_fixture as s
    import unified_manager_command as m
    import verify_ios_no_tproxy_receipt as v
    import pytest
    old,_,_=f.generate('wireGuard','tcp4','positive',None)
    new,_,_=f.generate('wireGuard','tcp4','positive',None,candidate=f.NO_TPROXY_CANDIDATE)
    split,_,_,_=s.generate('excluded','udp6',0xc0a80122,no_tproxy=True)
    assert old['candidateManifestSHA256']==f.CONTAINING_CANDIDATE
    assert new['candidateManifestSHA256']==f.NO_TPROXY_CANDIDATE
    assert split['candidateManifestSHA256']==f.NO_TPROXY_SPLIT_CANDIDATE
    assert len(set([f.CONTAINING_CANDIDATE,f.SPLIT_CANDIDATE,f.NO_TPROXY_CANDIDATE,f.NO_TPROXY_SPLIT_CANDIDATE]))==4
    assert m.command(new,'prepare')['owner']==new['owner']
    assert m.command(split,'prepare')['owner']==split['owner']
    p=tmp_path/'untrusted';p.mkdir();(p/'manifest.json').write_text('{}');d=tmp_path/'destination';d.mkdir();(d/'libtun2proxy.a').write_bytes(b'original')
    with pytest.raises(ValueError):v.verify(p,d)
    assert (d/'libtun2proxy.a').read_bytes()==b'original'
    b=(IOS/'Tools/build_product_unified_candidate_unsigned.sh').read_text()
    assert 'NO_TPROXY_REQUIRES_ISOLATED_HOST' in b and 'provider_link_map_sha256' in b and 'LD_GENERATE_MAP_FILE=YES' in b
