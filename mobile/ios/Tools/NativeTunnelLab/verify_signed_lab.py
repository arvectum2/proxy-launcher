"""Reject provisioning/signature scope outside isolated development IDs."""
import plistlib, subprocess, sys
from pathlib import Path
host = Path(sys.argv[1])
team = "VML75VY94V"
base = "ru.arvectum.proxylauncher.lab.nativeqa"
for bundle, ident in [(host,base),(host/"PlugIns/NativeLab.appex",base+".PacketTunnel")]:
    assert plistlib.loads((bundle/"Info.plist").read_bytes())["CFBundleIdentifier"] == ident
    profile = plistlib.loads(subprocess.check_output(["security","cms","-D","-i",str(bundle/"embedded.mobileprovision")],stderr=subprocess.DEVNULL))
    e = profile["Entitlements"]
    assert e["application-identifier"] == team+"."+ident
    assert e["get-task-allow"] is True
    assert "packet-tunnel-provider" in e["com.apple.developer.networking.networkextension"]
    assert "00008110-001C51810A12401E" in profile["ProvisionedDevices"]
    actual = plistlib.loads(subprocess.check_output(["codesign","-d","--entitlements",":-",str(bundle)],stderr=subprocess.DEVNULL))
    assert actual["application-identifier"] == team+"."+ident
    assert actual["get-task-allow"] is True
    assert actual["com.apple.developer.networking.networkextension"] == ["packet-tunnel-provider"]
    assert not actual.get("com.apple.security.application-groups")
    assert all(group == team+"."+ident for group in actual.get("keychain-access-groups",[]))
    print("VERIFIED_LAB_DEVELOPMENT_SIGNATURE",ident)
