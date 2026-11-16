#!/usr/bin/env python3
"""Sign one isolated NativeLab build with existing offline device-bound profiles."""
import datetime
import hashlib
import json
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile

from stage_nativeqa_isolated import LAB, TEAM, SHARED

HOST = "NativeLabHost.app"
EXT = "Arvectum Packet Tunnel.appex"
DEVICE = "00008110-001C51810A12401E"


def need(condition, reason):
    if not condition:
        raise ValueError(reason)


def sha(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def file_map(root):
    need(root.is_dir() and not root.is_symlink(), "invalid bundle")
    paths = list(root.rglob("*"))
    need(not any(p.is_symlink() for p in paths), "unexpected bundle symlink")
    return {str(p.relative_to(root)): sha(p) for p in sorted(paths) if p.is_file()}


def decode_profile(path):
    return plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(path)], stderr=subprocess.DEVNULL, timeout=15))


def expected_entitlements(profile, ident, now):
    e = profile["Entitlements"]
    app_id = TEAM + "." + ident
    need(ident in (LAB, LAB+".PacketTunnel"), "not lab identity")
    need(profile["TeamIdentifier"] == [TEAM] and profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc) > now, "wrong or expired profile")
    need(DEVICE in profile.get("ProvisionedDevices", []) and not profile.get("ProvisionsAllDevices"), "wrong device")
    need(e["application-identifier"] == app_id and e["com.apple.developer.team-identifier"] == TEAM and e["get-task-allow"] is True, "development identity mismatch")
    need("packet-tunnel-provider" in e.get("com.apple.developer.networking.networkextension", []), "no packet tunnel capability")
    need(not e.get("com.apple.security.application-groups") and not e.get("com.apple.developer.icloud-container-identifiers"), "unexpected profile capabilities")
    groups=e.get("keychain-access-groups", [])
    need(SHARED in groups or TEAM+".*" in groups, "isolated keychain group not allowed")
    return {"application-identifier": app_id, "com.apple.developer.team-identifier": TEAM,
            "get-task-allow": True, "com.apple.developer.networking.networkextension": ["packet-tunnel-provider"],
            "keychain-access-groups": [SHARED]}


def sign(source, output, host_profile, ext_profile, manifest_hash):
    manifest_path=source/"manifest.json"
    need(sha(manifest_path)==manifest_hash, "manifest hash mismatch")
    m=json.loads(manifest_path.read_text())
    need(m.get("isolated_nativeqa") is True and m.get("native_runtime_qa_harness") is True and m.get("native_exact_dns") is True and m.get("runtime_authorized") is False and m.get("release_authorized") is False, "wrong lab candidate")
    need(m["bundle_files"]==file_map(source/HOST), "unsigned bundle content mismatch")
    need(not output.exists(), "output already exists")
    now=datetime.datetime.now(datetime.timezone.utc)
    profiles=[decode_profile(p) for p in (host_profile,ext_profile)]
    certs=[{hashlib.sha1(c).hexdigest().upper() for c in p["DeveloperCertificates"]} for p in profiles]
    available=subprocess.check_output(["security","find-identity","-v","-p","codesigning"],text=True,timeout=15)
    certs={c for c in certs[0]&certs[1] if c in available}
    need(len(certs)==1, "no unique existing signing identity")
    cert=certs.pop()
    with tempfile.TemporaryDirectory(prefix="apl-nativeqa-sign-") as temp:
        app=pathlib.Path(temp)/HOST
        shutil.copytree(source/HOST,app)
        ext=app/"PlugIns"/EXT
        need(list((app/"PlugIns").iterdir())==[ext], "unexpected extension")
        by_role=[(app,LAB,host_profile,profiles[0]),(ext,LAB+".PacketTunnel",ext_profile,profiles[1])]
        for bundle,ident,profile_path,profile in reversed(by_role):
            info=plistlib.loads((bundle/"Info.plist").read_bytes())
            need(info["CFBundleIdentifier"]==ident and info["APLKeychainAccessGroup"]==SHARED, "bundle isolation mismatch")
            need(not (bundle/"embedded.mobileprovision").exists(), "unexpected prior signature")
            if ident.endswith(".PacketTunnel"):
                need(info["NSExtension"]["NSExtensionPointIdentifier"]=="com.apple.networkextension.packet-tunnel", "wrong provider type")
            ent=expected_entitlements(profile,ident,now)
            plist=pathlib.Path(temp)/(ident+".plist")
            plist.write_bytes(plistlib.dumps(ent))
            shutil.copyfile(profile_path,bundle/"embedded.mobileprovision")
            # No unexpected executable plug-ins; sign nested SDK code if present.
            nested=[p for p in (bundle/"Frameworks").iterdir() if p.suffix in (".framework",".dylib")] if (bundle/"Frameworks").is_dir() else []
            for p in nested:
                subprocess.run(["codesign","--force","--sign",cert,"--timestamp=none",str(p)],check=True,timeout=60)
            subprocess.run(["codesign","--force","--sign",cert,"--entitlements",str(plist),"--generate-entitlement-der","--timestamp=none",str(bundle)],check=True,timeout=60)
            actual=plistlib.loads(subprocess.check_output(["codesign","-d","--entitlements",":-",str(bundle)],stderr=subprocess.DEVNULL))
            need(actual==ent,"signed entitlement drift")
            subprocess.run(["codesign","--verify","--strict",str(bundle)],check=True,timeout=30)
        subprocess.run(["codesign","--verify","--deep","--strict",str(app)],check=True,timeout=30)
        output.mkdir(mode=0o700)
        shutil.copytree(app,output/HOST)
        result=dict(schema=1,source_commit=m["source_commit"],unsigned_manifest_sha256=manifest_hash,
                    bundle_ids=[LAB,LAB+".PacketTunnel"],keychain_access_group=SHARED,
                    signing_identity_sha1=cert,profile_sha256=[sha(host_profile),sha(ext_profile)],
                    signed_files=file_map(output/HOST),runtime_authorized=False,release_authorized=False)
        (output/"signed-manifest.json").write_text(json.dumps(result,sort_keys=True,indent=2)+"\n")
        subprocess.run(["codesign","--verify","--deep","--strict",str(output/HOST)],check=True,timeout=30)
        print("ISOLATED_NATIVEQA_SIGNED_PASS",sha(output/"signed-manifest.json"))


if __name__=="__main__":
    if len(sys.argv)!=6:
        raise SystemExit("usage: sign_isolated_nativeqa.py UNSIGNED_DIR NEW_SIGNED_DIR HOST_PROFILE EXT_PROFILE TRUSTED_MANIFEST_SHA256")
    sign(*map(pathlib.Path,sys.argv[1:5]),sys.argv[5])
