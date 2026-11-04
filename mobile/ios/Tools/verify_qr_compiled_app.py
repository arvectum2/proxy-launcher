#!/usr/bin/env python3
"""Read-only compiled iOS QR check; never proves Apple signing/publication."""
import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys

source_script = Path(__file__).with_name("verify_release_feature_source.py")
spec = importlib.util.spec_from_file_location("apl_ios_source", source_script)
source_gate = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = source_gate
spec.loader.exec_module(source_gate)

APP_ID = "ru.arvectum.proxylauncher.ios"
EXT_ID = APP_ID + ".PacketTunnel"
SYMBOLS = {
    "sender": "ProxyShareView.",
    "qr_generator": "ProxyShareQRCode.image(",
    "share_codec": "ProxyProfileSharing.deepLink(",
    "camera_scanner": "ProxyQRScanner.Coordinator.metadataOutput(",
}

def plist(path):
    if not path.is_file():
        raise ValueError("Missing Info.plist")
    try:
        with path.open("rb") as f:
            data = plistlib.load(f)
        if not isinstance(data, dict):
            raise ValueError("Invalid Info.plist")
        return data
    except (OSError, plistlib.InvalidFileException) as e:
        raise ValueError("Invalid Info.plist") from e

def binaries(app, name):
    if not name or "/" in name or name in (".", ".."):
        raise ValueError("Invalid executable name")
    exe = app / name
    if not exe.is_file():
        raise ValueError("Missing app executable")
    return [exe] + sorted(p for p in app.glob("*.debug.dylib") if p.is_file())

def demangle(path):
    nm = subprocess.run(["nm", "-a", str(path)], capture_output=True,
                        text=True, check=False)
    if nm.returncode:
        raise ValueError("Cannot inspect compiled symbols")
    proc = subprocess.run(["xcrun", "swift-demangle"], input=nm.stdout,
                          capture_output=True, text=True, check=False)
    if proc.returncode:
        raise ValueError("Cannot demangle compiled Swift")
    return proc.stdout

def attest(app, source_ref):
    source = source_gate.source_status(source_ref, "qr-profile-share")
    if not source["source_feature_present"]:
        raise ValueError("QR source commit not included")
    if app.suffix != ".app" or not app.is_dir():
        raise ValueError("App bundle missing")
    info = plist(app / "Info.plist")
    if info.get("CFBundleIdentifier") != APP_ID:
        raise ValueError("Wrong app bundle identifier")
    extension = app / "PlugIns" / "Arvectum Packet Tunnel.appex"
    if not extension.is_dir() or plist(extension / "Info.plist").get("CFBundleIdentifier") != EXT_ID:
        raise ValueError("Wrong or missing PacketTunnel extension")
    all_symbols = "\n".join(demangle(p) for p in binaries(app, str(info.get("CFBundleExecutable", ""))))
    found = {key: needle in all_symbols for key, needle in SYMBOLS.items()}
    if not all(found.values()):
        raise ValueError("Required compiled QR symbols missing")
    return {
        "source_commit": source["source_commit"],
        "compiled_qr_in_local_app": True,
        "compiled_symbols": found,
        "bundle_identifier": APP_ID,
        "bundle_version": str(info.get("CFBundleShortVersionString", "")),
        "bundle_build": str(info.get("CFBundleVersion", "")),
        "apple_signed_archive_verified": False,
        "app_store_publication_verified": False,
        "two_iphone_qa_verified": False,
    }

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--app", type=Path, required=True)
    p.add_argument("--source-ref", required=True)
    args = p.parse_args()
    try:
        report = attest(args.app, args.source_ref)
    except (ValueError, OSError) as e:
        print(f"Unverified compiled app: {e}", file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
