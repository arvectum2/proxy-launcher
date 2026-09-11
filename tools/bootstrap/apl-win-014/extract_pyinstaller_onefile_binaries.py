#!/usr/bin/env python3
"""Extract exact native binary entries from a PyInstaller one-file executable.

The APL-WIN-014 enforced App Control stand must authorize not only the outer
Arvectum executable but also the native PE payload that the PyInstaller
bootloader materializes under ``%TEMP%\\_MEI*`` at runtime.  This helper uses
the PyInstaller version already pinned in the Windows build environment and
extracts only CArchive entries whose type code is ``b`` (native binaries).

The result is deterministic evidence bound to the exact source executable.
No executable is launched and no Windows security control is modified.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import sys

import PyInstaller
from PyInstaller.archive.readers import CArchiveReader


SCHEMA = "arvectum.proxy.apl-win-014-pyinstaller-native-runtime.v1"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_relative_name(name: str) -> PurePosixPath:
    normalized = name.replace("\\", "/")
    relative = PurePosixPath(normalized)
    if relative.is_absolute() or not relative.parts:
        raise ValueError(f"Unsafe PyInstaller archive path: {name!r}")
    if any(part in ("", ".", "..") for part in relative.parts):
        raise ValueError(f"Unsafe PyInstaller archive path: {name!r}")
    if ":" in relative.parts[0]:
        raise ValueError(f"Unsafe PyInstaller archive path: {name!r}")
    return relative


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_exe", type=Path)
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args()

    source = args.source_exe.resolve(strict=True)
    output = args.output_directory.resolve()
    evidence_path = args.evidence.resolve()

    if output.exists():
        raise SystemExit(f"Output directory already exists: {output}")
    if evidence_path.exists():
        raise SystemExit(f"Evidence file already exists: {evidence_path}")

    output.mkdir(parents=True, exist_ok=False)

    try:
        archive = CArchiveReader(str(source))
        entries: list[dict[str, object]] = []
        total_size = 0

        for name in sorted(archive.toc):
            *_, typecode = archive.toc[name]
            if typecode != "b":
                continue

            relative = safe_relative_name(name)
            data = archive.extract(name)
            destination = output.joinpath(*relative.parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)

            digest = sha256_bytes(data)
            actual_digest = sha256_file(destination)
            if actual_digest != digest:
                raise RuntimeError(f"Post-write SHA256 mismatch for {relative.as_posix()}")

            size = len(data)
            total_size += size
            entries.append(
                {
                    "path": relative.as_posix(),
                    "size": size,
                    "sha256": digest,
                    "typecode": "b",
                }
            )

        if not entries:
            raise RuntimeError("PyInstaller CArchive contains no native binary entries.")

        names_lower = {Path(str(item["path"])).name.lower() for item in entries}
        for required in ("python312.dll", "ucrtbase.dll"):
            if required not in names_lower:
                raise RuntimeError(f"Required native runtime binary missing from archive: {required}")

        evidence = {
            "schema": SCHEMA,
            "source_executable": source.name,
            "source_application_sha256": sha256_file(source),
            "pyinstaller_version": PyInstaller.__version__,
            "archive_binary_typecode": "b",
            "binary_count": len(entries),
            "total_size": total_size,
            "required_runtime_binaries": ["python312.dll", "ucrtbase.dll"],
            "entries": entries,
            "result": "PASS",
        }

        evidence_path.parent.mkdir(parents=True, exist_ok=True)
        evidence_path.write_text(
            json.dumps(evidence, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except Exception:
        shutil.rmtree(output, ignore_errors=True)
        raise

    print(f"PYINSTALLER_NATIVE_RUNTIME_BINARY_COUNT={len(entries)}")
    print(f"PYINSTALLER_NATIVE_RUNTIME_TOTAL_SIZE={total_size}")
    print(f"PYINSTALLER_NATIVE_RUNTIME_SOURCE_SHA256={evidence['source_application_sha256']}")
    print(f"PYINSTALLER_NATIVE_RUNTIME_EVIDENCE={evidence_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
