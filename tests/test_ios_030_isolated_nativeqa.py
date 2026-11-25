"""The NativeLab staging/signing boundary must never name owner credentials."""
import datetime
from pathlib import Path
import plistlib
import shutil
import sys

import pytest

IOS=Path(__file__).resolve().parents[1]/"mobile/ios"
sys.path.insert(0,str(IOS/"Tools"))
from stage_nativeqa_isolated import stage, LAB, PRODUCT, TEAM, SHARED
from sign_isolated_nativeqa import expected_entitlements, DEVICE


def test_isolated_stage(tmp_path):
    root=tmp_path/"ios"
    root.mkdir()
    for folder in ("App","Shared","SharedCore","PacketTunnel","Config"):
        shutil.copytree(IOS/folder, root/folder)
    shutil.copyfile(IOS/"project.yml",root/"project.yml")
    before=(IOS/"Shared/AppShared.swift").read_bytes()
    stage(root)
    assert (IOS/"Shared/AppShared.swift").read_bytes()==before
    assert SHARED in (root/"Shared/AppShared.swift").read_text()
    assert PRODUCT not in (root/"Shared/AppShared.swift").read_text()
    for n in ("App","PacketTunnel"):
        e=plistlib.loads((root/"Config"/(n+".entitlements")).read_bytes())
        assert e=={"com.apple.developer.networking.networkextension":["packet-tunnel-provider"],"keychain-access-groups":[SHARED]}
        i=plistlib.loads((root/"Config"/(n+"-Info.plist")).read_bytes())
        assert i["APLKeychainAccessGroup"]==SHARED
        assert not {"CFBundleURLTypes","UTExportedTypeDeclarations","SKAdNetworkItems"} & set(i)
    entry=(root/"App/ArvectumProxyLauncherApp.swift").read_text()
    assert "NativeRuntimeReviewQAView()" in entry and "ordinaryRoot" not in entry and "YandexAds" not in entry
    assert "Optional(UserDefaults.standard)" in (root/"Shared/ProfileStore.swift").read_text()
    assert "APL NativeLab (isolated)" in (root/"App/VPNController.swift").read_text()
    lib=(root/"App/NativePersistentProfilesView.swift").read_text()
    assert "apl-nativeqa-fixture.txt" in lib and "attrs.isSymbolicLink != true" in lib
    assert 'endpoint.host == "192.168.1.80"' in lib and "records.count==1" in lib
    assert "FileManager.default.removeItem(at:url)" in lib and "session.previewTransfer(NativeImportTransfer(records))" in lib


def test_unknown_product_namespace_is_rejected(tmp_path):
    root=tmp_path/"ios"
    (root/"Shared").mkdir(parents=True)
    shared=root/"Shared/AppShared.swift"
    shared.write_text((IOS/"Shared/AppShared.swift").read_text()+'\nlet unexpected = "'+PRODUCT+'.new"\n')
    before=shared.read_bytes()
    with pytest.raises(AssertionError):
        stage(root)
    assert shared.read_bytes()==before



def profile(ident):
    return {"Entitlements":{"application-identifier":TEAM+"."+ident,
          "com.apple.developer.team-identifier":TEAM,"get-task-allow":True,
          "com.apple.developer.networking.networkextension":["packet-tunnel-provider"],
          "keychain-access-groups":[TEAM+".*","com.apple.token"]},
          "TeamIdentifier":[TEAM],"ExpirationDate":datetime.datetime(2030,1,1),
          "ProvisionedDevices":[DEVICE]}


@pytest.mark.parametrize("ident",[LAB,LAB+".PacketTunnel"])
def test_profile(ident):
    now=datetime.datetime.now(datetime.timezone.utc)
    actual=expected_entitlements(profile(ident),ident,now)
    assert actual["keychain-access-groups"]==[SHARED]
    assert actual["application-identifier"]==TEAM+"."+ident
    assert actual["com.apple.developer.networking.networkextension"]==["packet-tunnel-provider"]
    assert "com.apple.security.application-groups" not in actual


@pytest.mark.parametrize("damage",[
    lambda p:p.update(ProvisionedDevices=[]),
    lambda p:p.update(ProvisionsAllDevices=True),
    lambda p:p.update(ExpirationDate=datetime.datetime(2000,1,1)),
    lambda p:p["Entitlements"].update({"get-task-allow":False}),
    lambda p:p["Entitlements"].update({"keychain-access-groups":[TEAM+"."+PRODUCT+".shared"]}),
    lambda p:p["Entitlements"].update({"com.apple.security.application-groups":["group."+PRODUCT]}),
    lambda p:p["Entitlements"].update({"application-identifier":TEAM+"."+PRODUCT}),
])
def test_profile_fails_closed(damage):
    p=profile(LAB)
    damage(p)
    with pytest.raises(ValueError):
        expected_entitlements(p,LAB,datetime.datetime.now(datetime.timezone.utc))
