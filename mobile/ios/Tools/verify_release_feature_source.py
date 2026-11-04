#!/usr/bin/env python3
"""Read-only Git provenance for an iOS release's source feature inclusion.

This proves only that required source commits and files are present at a Git
commit. It NEVER proves that a signed IPA includes the feature or that Apple
approved/published it. Use signed binary and device tests for that separate gate.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys

REPO = Path(__file__).resolve().parents[3]
FEATURES = {
    "qr-profile-share": {
        # PR #320's corrected, source-validated QR sender+receiver implementation.
        "required_commit": "b59801f69990d621e873360762256a80919168de",
        "required_files": (
            "mobile/ios/SharedCore/ProxyProfileSharing.swift",
            "mobile/ios/App/ProxyShareView.swift",
            "mobile/ios/App/ProxyQRScanner.swift",
        ),
    },
    "safe-connection-diagnostics": {
        # PR #312's last typed, localized VPN permission guidance change.
        "required_commit": "65e7e6535154c9db1a56cd34aadffee292c4b43d",
        "required_files": (
            "mobile/ios/SharedCore/ProxyFailureReason.swift",
            "mobile/ios/App/VPNController.swift",
        ),
    },
}


def git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(REPO), *args],
        capture_output=True, text=True, check=False,
    )


def commit_sha(ref: str) -> str:
    # Prevent ambiguous option parsing for untrusted caller refs.
    response = git("rev-parse", "--verify", "--end-of-options", ref + "^{commit}")
    if response.returncode != 0:
        raise ValueError(f"Unknown local Git commit/ref: {ref!r}")
    return response.stdout.strip()


def source_status(source_ref: str, feature: str) -> dict[str, object]:
    source = commit_sha(source_ref)
    info = FEATURES[feature]
    required = commit_sha(str(info["required_commit"]))
    ancestor = git("merge-base", "--is-ancestor", required, source)
    if ancestor.returncode not in (0, 1):
        raise ValueError("Git ancestry could not be verified")
    required_files = tuple(info["required_files"])
    present = all(
        git("cat-file", "-e", f"{source}:{path}").returncode == 0
        for path in required_files
    )
    included = ancestor.returncode == 0 and present
    return {
        "feature": feature,
        "source_commit": source,
        "required_commit": required,
        "required_file_count": len(required_files),
        "required_files_present": present,
        "required_commit_ancestor": ancestor.returncode == 0,
        "source_feature_present": included,
        "signed_binary_feature_verified": False,
        "app_store_publication_verified": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-ref", required=True,
                        help="Exact source Git SHA used for the intended build")
    parser.add_argument("--feature", choices=sorted(FEATURES), required=True)
    gate = parser.add_mutually_exclusive_group()
    gate.add_argument("--require-present", action="store_true")
    gate.add_argument("--require-absent", action="store_true")
    args = parser.parse_args()
    try:
        status = source_status(args.source_ref, args.feature)
    except ValueError as exc:
        print(f"Unverified source: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(status, indent=2, sort_keys=True))
    present = status["source_feature_present"]
    if (args.require_present and not present) or (args.require_absent and present):
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
