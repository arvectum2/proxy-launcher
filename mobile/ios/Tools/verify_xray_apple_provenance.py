#!/usr/bin/env python3
"""Fail-closed offline provenance inspection. Never extracts or executes assets.

This does NOT verify upstream code signatures, dependency licenses, Go build
reproducibility or production iOS suitability. Those are separate release gates.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import zipfile

PIN = Path(__file__).with_name("xray_apple_pinned_asset.json")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify(asset: Path, go_mod: Path, pin: Path = PIN) -> dict:
    settings = json.loads(pin.read_text(encoding="utf-8"))
    if asset.name != settings["asset"] or not asset.is_file() or asset.stat().st_size > 150 * 1024 * 1024:
        raise ValueError("wrong asset name/type/size")
    if sha256(asset) != settings["sha256"]:
        raise ValueError("untrusted Apple artifact digest")
    if not go_mod.is_file() or go_mod.stat().st_size > 128 * 1024 or sha256(go_mod) != settings["go_mod_sha256"]:
        raise ValueError("untrusted pinned go.mod digest")
    text = go_mod.read_text(encoding="utf-8")
    if "module github.com/xtls/libxray" not in text:
        raise ValueError("wrong Go source module")
    if f'{settings["xray_core_module"]} {settings["xray_core_version"]}' not in text:
        raise ValueError("unexpected xray-core source version")
    # Matches both direct and // indirect require entries, not replace lines.
    modules = re.findall(r"^\s+([\w.\-/]+)\s+(v\S+)", text, re.M)
    if len(modules) < 30 or len(modules) != len({name for name, _ in modules}):
        raise ValueError("missing or duplicate Go dependencies")
    with zipfile.ZipFile(asset) as archive:
        names = set()
        total = 0
        for entry in archive.infolist():
            member = PurePosixPath(entry.filename)
            if member.is_absolute() or ".." in member.parts or "\\" in entry.filename:
                raise ValueError("unsafe archive member path")
            if stat.S_IFMT(entry.external_attr >> 16) == stat.S_IFLNK:
                raise ValueError("symlink in pinned archive")
            if entry.filename in names:
                raise ValueError("duplicate archive member")
            names.add(entry.filename)
            total += entry.file_size
            if total > 1300 * 1024 * 1024:
                raise ValueError("unbounded expanded archive")
        required = settings["required_archive_members"]
        if not all(name in names for name in required):
            raise ValueError("missing Apple iPhoneOS/Simulator static libraries")
    return {
        "tag": settings["tag"], "source_tag_commit": settings["tag_commit"],
        "asset_sha256": settings["sha256"], "go_mod_sha256": settings["go_mod_sha256"],
        "xray_core_version": settings["xray_core_version"],
        "declared_go_modules": len(modules), "archive_members": len(names),
        "status": "provenance_hashes_and_structure_match_only",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", required=True, type=Path)
    parser.add_argument("--go-mod", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.asset, args.go_mod), ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
