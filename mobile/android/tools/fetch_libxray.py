#!/usr/bin/env python3
"""Fetch the pinned libXray Android AAR with digest verification."""

from __future__ import annotations

import hashlib
import shutil
import tempfile
import urllib.request
import zipfile
from pathlib import Path

VERSION = "v26.9.9"
ARCHIVE_SHA256 = "4998a8b56e4a78a164b5359d5690036f83da3b575465cea57ddf29c0149c345f"
URL = f"https://github.com/XTLS/libXray/releases/download/{VERSION}/libxray-android.zip"
ROOT = Path(__file__).resolve().parents[1]
LIBS = ROOT / "app" / "libs"
AAR = LIBS / "libXray.aar"
MARKER = LIBS / ".libxray-version"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="apl-libxray-") as tmp:
        archive = Path(tmp) / "libxray-android.zip"
        print(f"Fetching libXray {VERSION}...")
        with urllib.request.urlopen(URL, timeout=180) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)

        actual = sha256(archive)
        if actual != ARCHIVE_SHA256:
            raise SystemExit(
                f"libXray SHA-256 mismatch: expected {ARCHIVE_SHA256}, got {actual}"
            )

        with zipfile.ZipFile(archive) as bundle:
            candidates = [
                name for name in bundle.namelist()
                if name.endswith("/libXray.aar") or name == "libXray.aar"
            ]
            if len(candidates) != 1:
                raise SystemExit(f"Expected exactly one libXray.aar, found {candidates}")
            LIBS.mkdir(parents=True, exist_ok=True)
            with bundle.open(candidates[0]) as source, AAR.open("wb") as output:
                shutil.copyfileobj(source, output)

        MARKER.write_text(
            f"{VERSION}\nsha256={ARCHIVE_SHA256}\n",
            encoding="utf-8",
        )
        print(f"libXray verified and installed at {AAR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
