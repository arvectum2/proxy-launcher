#!/usr/bin/env python3
"""Fetch the pinned tun2proxy Android native libraries with digest verification."""

from __future__ import annotations

import hashlib
import shutil
import tempfile
import urllib.request
import zipfile
from pathlib import Path

VERSION = "v0.8.3"
ARCHIVE_SHA256 = "50706ce2b0799295b6672cf6b72ec388d02a3104ebd1195b3a9bca10d2bd80f5"
URL = f"https://github.com/tun2proxy/tun2proxy/releases/download/{VERSION}/tun2proxy-android-libs.zip"
ABIS = ("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
ROOT = Path(__file__).resolve().parents[1]
JNI_LIBS = ROOT / "app" / "src" / "main" / "jniLibs"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="apl-tun2proxy-") as tmp:
        archive = Path(tmp) / "tun2proxy-android-libs.zip"
        print(f"Fetching tun2proxy {VERSION}...")
        with urllib.request.urlopen(URL, timeout=120) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)

        actual = sha256(archive)
        if actual != ARCHIVE_SHA256:
            raise SystemExit(f"tun2proxy SHA-256 mismatch: expected {ARCHIVE_SHA256}, got {actual}")

        with zipfile.ZipFile(archive) as bundle:
            names = bundle.namelist()
            for abi in ABIS:
                suffix = f"/{abi}/libtun2proxy.so"
                matches = [name for name in names if name.endswith(suffix)]
                if len(matches) != 1:
                    raise SystemExit(f"Expected exactly one {suffix} in archive, found {matches}")
                target_dir = JNI_LIBS / abi
                target_dir.mkdir(parents=True, exist_ok=True)
                target = target_dir / "libtun2proxy.so"
                with bundle.open(matches[0]) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
                print(f"Installed {target.relative_to(ROOT)}")

        marker = JNI_LIBS / ".tun2proxy-version"
        marker.write_text(f"{VERSION}\nsha256={ARCHIVE_SHA256}\n", encoding="utf-8")
        print("tun2proxy native libraries verified and installed.")


if __name__ == "__main__":
    main()
