#!/usr/bin/env python3
"""Read-only guard against building the obsolete iOS 0.1.42 source as iOS 0.2.

Run this before XcodeGen, Swift tests and device builds on the 0.2 feature
branch. Version bumps require updating the tracked identity manifest too.
No Apple API, signing, VPN, or user-data operations occur here.
"""
from __future__ import annotations

import argparse
import json
import plistlib
import re
import zipfile
import sys
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parents[1]
IDENTITY_PATH = Path("mobile/ios/Config/active-development.json")
PROJECT_SPEC_PATH = Path("mobile/ios/project.yml")
XCODE_PROJECT_PATH = Path("mobile/ios/ArvectumProxyLauncherIOS.xcodeproj/project.pbxproj")
RSYA_CONFIG_PATH = Path("mobile/ios/App/SettingsBannerView.swift")
RSYA_NATIVE_PATH = Path("mobile/ios/App/NativeHomeAdView.swift")
RSYA_HOME_PATH = Path("mobile/ios/App/ContentView.swift")
RSYA_APP_PATH = Path("mobile/ios/App/ArvectumProxyLauncherApp.swift")
RSYA_INFO_PATH = Path("mobile/ios/Config/App-Info.plist")


def verify_rsya_release_sources(root: Path) -> None:
    """Mandatory paid-ad integration: release config, both placements, SDK and SKAd.

    This structural gate deliberately does NOT claim the ad provider will
    always have inventory or the network will always allow ad requests.
    """
    ad = (root / RSYA_CONFIG_PATH).read_text(encoding="utf-8")
    app = (root / RSYA_APP_PATH).read_text(encoding="utf-8")
    native = (root / RSYA_NATIVE_PATH).read_text(encoding="utf-8")
    home = (root / RSYA_HOME_PATH).read_text(encoding="utf-8")
    spec = (root / PROJECT_SPEC_PATH).read_text(encoding="utf-8")
    parts = ad.split("#if DEBUG", 1)
    if len(parts) < 2 or "#else" not in parts[1] or "#endif" not in parts[1]:
        raise ValueError("RSYA Debug and Release gates not distinguishable")
    release = parts[1].split("#else", 1)[1].split("#endif", 1)[0]
    if not all(token in ad for token in (
        'productionBannerUnitID = "R-M-20288304-1"',
        'nativeAdUnitID = "R-M-20288304-2"',
    )):
        raise ValueError("RSYA production placements missing or mismatched")
    if not all(token in release for token in (
        "static let isEnabled = true",
        "activeBannerUnitID = productionBannerUnitID",
        "activeNativeAdUnitID = nativeAdUnitID",
    )):
        raise ValueError("RSYA disabled or demo unit selected in iOS Release")
    if ("AdRequest(adUnitID: IOSAdsConfig.activeBannerUnitID)" not in ad
            or "AdRequest(adUnitID: IOSAdsConfig.activeNativeAdUnitID)" not in native):
        raise ValueError("RSYA production ad requests not wired to SDK")
    if ("SettingsBannerView(" not in home or "NativeHomeAdView(" not in home
            or "YandexAds.initializeSDK(" not in app):
        raise ValueError("RSYA placements or SDK startup missing from Home")
    if ("package: YandexMobileAds" not in spec or "product: YandexMobileAds" not in spec):
        raise ValueError("RSYA SDK not linked to iOS app")
    info = plistlib.loads((root / RSYA_INFO_PATH).read_bytes())
    if not info.get("SKAdNetworkItems"):
        raise ValueError("RSYA SKAdNetwork identifiers missing")


def verify_rsya_exported_ipa(path: Path, version: str, build: str) -> None:
    """Check the ACTUAL distributable payload, not just source code."""
    with zipfile.ZipFile(path) as bundle:
        if bundle.testzip() is not None:
            raise ValueError("RSYA release IPA ZIP integrity failure")
        prefix = "Payload/Arvectum Proxy Launcher.app/"
        files = set(bundle.namelist())
        if prefix + "Info.plist" not in files:
            raise ValueError("iOS IPA app Info.plist missing")
        info = plistlib.loads(bundle.read(prefix + "Info.plist"))
        if (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != (version, build):
            raise ValueError("iOS IPA version and build do not match active source")
        if not info.get("SKAdNetworkItems"):
            raise ValueError("RSYA released IPA SKAdNetwork items missing")
        if prefix + "Frameworks/YandexMobileAds.framework/YandexMobileAds" not in files:
            raise ValueError("RSYA released IPA lacks actual YandexMobileAds framework binary")
        if prefix + "PlugIns/Arvectum Packet Tunnel.appex/Info.plist" not in files:
            raise ValueError("RSYA released IPA lacks its mandatory Packet Tunnel")
        if prefix + "_CodeSignature/CodeResources" not in files:
            raise ValueError("RSYA released IPA app signature missing")




def verify_active_release(root: Path) -> tuple[str, str]:
    root = Path(root)
    identity = json.loads((root / IDENTITY_PATH).read_text(encoding="utf-8"))
    if identity.get("platform") != "ios":
        raise ValueError("Active release identity is not for iOS")
    if identity.get("release_state") != "source_candidate_not_uploaded":
        raise ValueError("Unexpected release state; review the active development manifest")
    if identity.get("app_store_submission_authorized") is not False:
        raise ValueError("Source-only release gate must not authorize App Store submission")
    version = identity.get("marketing_version")
    build = identity.get("build_number")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid active iOS marketing version")
    if not isinstance(build, str) or not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("Invalid active iOS build number")
    spec = (root / PROJECT_SPEC_PATH).read_text(encoding="utf-8")
    pbx = (root / XCODE_PROJECT_PATH).read_text(encoding="utf-8")
    spec_versions = re.findall(r'^\s*MARKETING_VERSION:\s*"([^"]+)"\s*$', spec, re.M)
    spec_builds = re.findall(r'^\s*CURRENT_PROJECT_VERSION:\s*"([^"]+)"\s*$', spec, re.M)
    pbx_versions = re.findall(r'^\s*MARKETING_VERSION\s*=\s*([^;]+);\s*$', pbx, re.M)
    pbx_builds = re.findall(r'^\s*CURRENT_PROJECT_VERSION\s*=\s*([^;]+);\s*$', pbx, re.M)
    if spec_versions != [version] or spec_builds != [build]:
        raise ValueError(f"Stale XcodeGen iOS version: expected {version} ({build})")
    if len(pbx_versions) < 2 or set(pbx_versions) != {version}:
        raise ValueError(f"Stale generated iOS Xcode project marketing version: expected {version}")
    if len(pbx_builds) < 2 or set(pbx_builds) != {build}:
        raise ValueError(f"Stale generated iOS Xcode project build number: expected {build}")
    verify_rsya_release_sources(root)
    return version, build


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--ipa", type=Path,
                        help="Also assert signed/exported IPA contains the production ad SDK")
    args = parser.parse_args()
    try:
        version, build = verify_active_release(args.root)
        if args.ipa is not None:
            verify_rsya_exported_ipa(args.ipa, version, build)
    except (OSError, ValueError, json.JSONDecodeError, zipfile.BadZipFile) as exc:
        print(f"iOS ACTIVE RELEASE PREFLIGHT FAILED: {exc}", file=sys.stderr)
        return 2
    print(f"iOS active source and mandatory RSYA verified: {version} ({build}); no Apple upload")
    if args.ipa is not None:
        print("RSYA_PRODUCTION_IPA_SDK_AND_SIGNATURE_GATE_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
