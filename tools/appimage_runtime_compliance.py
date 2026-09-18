#!/usr/bin/env python3
"""Build and verify the AppImage runtime compliance bundle.

This is an engineering distribution control. It binds notices and corresponding
source metadata to the exact hash-pinned AppImage type-2 runtime used by the
repository. It is not a legal opinion or a substitute for authorized legal review.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

SCHEMA = "arvectum.appimage-runtime-compliance.v1"
ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = ROOT / "tools" / "appimage-toolchain.lock"
SOURCE_LICENSE_DIR = ROOT / "third_party_licenses" / "appimage_runtime"
NOTICE_PATH = ROOT / "THIRD_PARTY_NOTICES.txt"

REQUIRED_LICENSES = (
    ("type2-runtime", "type2-runtime-LICENSE.txt"),
    ("libfuse", "libfuse-LICENSE.txt"),
    ("libfuse-lgpl-2.1", "libfuse-LGPL-2.1.txt"),
    ("libfuse-gpl-2.0", "libfuse-GPL-2.0.txt"),
    ("squashfuse", "squashfuse-LICENSE.txt"),
    ("zstd", "zstd-LICENSE.txt"),
    ("zlib", "zlib-LICENSE.txt"),
    ("musl", "musl-COPYRIGHT.txt"),
    ("mimalloc", "mimalloc-LICENSE.txt"),
)
NOTICE_TOKENS = (
    "AppImage type-2 runtime", "musl libc", "libfuse", "squashfuse",
    "libzstd", "zlib", "mimalloc",
)
LOCK_KEYS = (
    "APPIMAGE_RUNTIME_SOURCE_COMMIT", "APPIMAGE_RUNTIME_SHA256",
    "APPIMAGE_RUNTIME_REPOSITORY", "LIBFUSE_VERSION", "LIBFUSE_SOURCE_URL",
    "LIBFUSE_SOURCE_SHA256", "SQUASHFUSE_VERSION", "SQUASHFUSE_SOURCE_URL",
    "SQUASHFUSE_SOURCE_SHA256", "MIMALLOC_NOTICE_VERSION",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_lock() -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in LOCK_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        if not sep or not key or not value:
            raise RuntimeError(f"Malformed AppImage lock line: {raw!r}")
        values[key] = value
    missing = [key for key in LOCK_KEYS if not values.get(key)]
    if missing:
        raise RuntimeError(f"AppImage lock missing compliance keys: {missing}")
    for key in ("APPIMAGE_RUNTIME_SHA256", "LIBFUSE_SOURCE_SHA256", "SQUASHFUSE_SOURCE_SHA256"):
        value = values[key]
        if len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value.lower()):
            raise RuntimeError(f"Invalid SHA-256 in AppImage lock: {key}")
    return values


def build_bundle(output: Path) -> dict[str, object]:
    lock = read_lock()
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    records: list[dict[str, str]] = []
    for component, filename in REQUIRED_LICENSES:
        source = SOURCE_LICENSE_DIR / filename
        if not source.is_file() or source.stat().st_size <= 0:
            raise RuntimeError(f"Missing AppImage runtime license text: {source}")
        target = output / filename
        shutil.copyfile(source, target)
        records.append({"component": component, "path": filename, "sha256": sha256(target)})
    readme = SOURCE_LICENSE_DIR / "README.md"
    if not readme.is_file() or readme.stat().st_size <= 0:
        raise RuntimeError("Missing AppImage runtime compliance README")
    shutil.copyfile(readme, output / "README.md")
    manifest: dict[str, object] = {
        "schema": SCHEMA,
        "runtime": {
            "source_commit": lock["APPIMAGE_RUNTIME_SOURCE_COMMIT"],
            "sha256": lock["APPIMAGE_RUNTIME_SHA256"],
            "repository": lock["APPIMAGE_RUNTIME_REPOSITORY"],
        },
        "corresponding_source": {
            "libfuse": {
                "version": lock["LIBFUSE_VERSION"],
                "url": lock["LIBFUSE_SOURCE_URL"],
                "sha256": lock["LIBFUSE_SOURCE_SHA256"],
            },
            "squashfuse": {
                "version": lock["SQUASHFUSE_VERSION"],
                "url": lock["SQUASHFUSE_SOURCE_URL"],
                "sha256": lock["SQUASHFUSE_SOURCE_SHA256"],
            },
        },
        "mimalloc_notice_version": lock["MIMALLOC_NOTICE_VERSION"],
        "files": records,
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    verify_bundle(output)
    return manifest


def verify_bundle(output: Path) -> dict[str, object]:
    lock = read_lock()
    manifest_path = output / "manifest.json"
    if not manifest_path.is_file():
        raise RuntimeError(f"Missing AppImage runtime manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema") != SCHEMA:
        raise RuntimeError(f"Unexpected AppImage runtime schema: {manifest.get('schema')!r}")
    expected_runtime = {
        "source_commit": lock["APPIMAGE_RUNTIME_SOURCE_COMMIT"],
        "sha256": lock["APPIMAGE_RUNTIME_SHA256"],
        "repository": lock["APPIMAGE_RUNTIME_REPOSITORY"],
    }
    if manifest.get("runtime") != expected_runtime:
        raise RuntimeError("AppImage runtime identity does not match the repository lock")
    expected_source = {
        "libfuse": {
            "version": lock["LIBFUSE_VERSION"],
            "url": lock["LIBFUSE_SOURCE_URL"],
            "sha256": lock["LIBFUSE_SOURCE_SHA256"],
        },
        "squashfuse": {
            "version": lock["SQUASHFUSE_VERSION"],
            "url": lock["SQUASHFUSE_SOURCE_URL"],
            "sha256": lock["SQUASHFUSE_SOURCE_SHA256"],
        },
    }
    if manifest.get("corresponding_source") != expected_source:
        raise RuntimeError("AppImage corresponding-source metadata does not match the lock")
    if manifest.get("mimalloc_notice_version") != lock["MIMALLOC_NOTICE_VERSION"]:
        raise RuntimeError("mimalloc notice version does not match the lock")
    records = manifest.get("files")
    if not isinstance(records, list):
        raise RuntimeError("Malformed AppImage runtime license records")
    expected_components = {component for component, _ in REQUIRED_LICENSES}
    seen: set[str] = set()
    for record in records:
        if not isinstance(record, dict):
            raise RuntimeError("Malformed AppImage runtime license record")
        component = str(record.get("component", ""))
        rel = str(record.get("path", ""))
        expected_hash = str(record.get("sha256", ""))
        path = output / rel
        if component not in expected_components or not path.is_file() or path.stat().st_size <= 0:
            raise RuntimeError(f"Missing/unknown AppImage runtime license file: {record!r}")
        if sha256(path) != expected_hash:
            raise RuntimeError(f"AppImage runtime license hash mismatch: {rel}")
        seen.add(component)
    if seen != expected_components:
        raise RuntimeError(f"AppImage runtime license component mismatch: {sorted(expected_components - seen)}")
    readme = output / "README.md"
    if not readme.is_file() or readme.stat().st_size <= 0:
        raise RuntimeError("Missing AppImage runtime compliance README in bundle")
    notices = NOTICE_PATH.read_text(encoding="utf-8")
    missing_notice = [token for token in NOTICE_TOKENS if token not in notices]
    if missing_notice:
        raise RuntimeError(f"THIRD_PARTY_NOTICES missing AppImage runtime components: {missing_notice}")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--build", action="store_true")
    mode.add_argument("--verify", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.build:
            manifest = build_bundle(args.output.resolve())
            print(f"AppImage runtime compliance bundle built: {args.output} ({len(manifest['files'])} texts)")
        else:
            manifest = verify_bundle(args.output.resolve())
            print(f"AppImage runtime compliance bundle verified: {args.output} ({len(manifest['files'])} texts)")
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        print(f"APPIMAGE RUNTIME COMPLIANCE FAIL: {exc}")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
