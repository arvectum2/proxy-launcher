#!/usr/bin/env python3
from __future__ import annotations
import hashlib, shutil, tempfile, urllib.request, zipfile
from pathlib import Path

VERSION = "v0.8.3"
ARCHIVE_SHA256 = "7f09f01a11fef6d57477df8c32ad3d86ea7fa98ba3aa60099680785ca637ecfd"
URL = f"https://github.com/tun2proxy/tun2proxy/releases/download/{VERSION}/tun2proxy-aarch64-apple-ios-xcframework.zip"
ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "Frameworks" / "tun2proxy.xcframework"

def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def main() -> None:
    with tempfile.TemporaryDirectory(prefix="apl-ios-tun2proxy-") as tmpdir:
        archive = Path(tmpdir) / "tun2proxy.zip"
        print(f"Fetching tun2proxy {VERSION} for iOS...")
        with urllib.request.urlopen(URL, timeout=120) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
        actual = digest(archive)
        if actual != ARCHIVE_SHA256:
            raise SystemExit(f"tun2proxy SHA-256 mismatch: expected {ARCHIVE_SHA256}, got {actual}")
        extract = Path(tmpdir) / "extract"
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(extract)
        source = extract / "tun2proxy.xcframework"
        if not (source / "ios-arm64" / "libtun2proxy.a").is_file():
            raise SystemExit("Unexpected tun2proxy iOS archive layout")
        shutil.rmtree(TARGET, ignore_errors=True)
        TARGET.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, TARGET)
        (TARGET.parent / ".tun2proxy-version").write_text(f"{VERSION}\\nsha256={ARCHIVE_SHA256}\\n", encoding="utf-8")
        print(f"Installed {TARGET.relative_to(ROOT)}")

if __name__ == "__main__":
    main()
