#!/usr/bin/env python3
"""Read-only guard against building the obsolete iOS 0.1.42 source as iOS 0.2.

Run this before XcodeGen, Swift tests and device builds on the 0.2 feature
branch. Version bumps require updating the tracked identity manifest too.
No Apple API, signing, VPN, or user-data operations occur here.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parents[1]
IDENTITY_PATH = Path("mobile/ios/Config/active-development.json")
PROJECT_SPEC_PATH = Path("mobile/ios/project.yml")
XCODE_PROJECT_PATH = Path("mobile/ios/ArvectumProxyLauncherIOS.xcodeproj/project.pbxproj")


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
    return version, build


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    args = parser.parse_args()
    try:
        version, build = verify_active_release(args.root)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"iOS ACTIVE RELEASE PREFLIGHT FAILED: {exc}", file=sys.stderr)
        return 2
    print(f"iOS active source verified: {version} ({build}); source-only, no Apple upload")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
