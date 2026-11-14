#!/usr/bin/env python3
"""Verify local source-build manifest and digest, not a signed attestation."""
import argparse
import hashlib
import mmap
from pathlib import Path

VERSION = "v0.8.3"
COMMIT = "e271de19683937f23d3f8f0eb4df0a61fc4a6e50"
TOOLCHAIN = "1.98.1"
UPSTREAM = "7f09f01a11fef6d57477df8c32ad3d86ea7fa98ba3aa60099680785ca637ecfd"
FORCED_EXIT = b"Forcing exit now."
SLICES = {"ios-arm64": "patched_library_sha256",
          "ios-arm64-simulator": "patched_simulator_library_sha256"}


def verify(framework: Path, slice_name: str, *, require_connected_udp: bool = False) -> str:
    library = framework / slice_name / "libtun2proxy.a"
    stamp = framework.resolve().parent / ".tun2proxy-version"
    if slice_name not in SLICES or not library.is_file():
        raise ValueError("required library missing")
    with library.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as memory:
        if memory.find(FORCED_EXIT) >= 0:
            raise ValueError("unsafe forced-exit watchdog literal present")
        digest = hashlib.sha256(memory).hexdigest()
    if not stamp.is_file():
        raise ValueError("local source-build manifest missing")
    raw = stamp.read_text(encoding="utf-8").splitlines()
    if not raw or raw[0] != VERSION:
        raise ValueError("version mismatch")
    fields = {}
    for line in raw[1:]:
        key, sep, value = line.partition("=")
        if not sep or key in fields:
            raise ValueError("invalid manifest")
        fields[key] = value
    for key, expected in (("source_commit", COMMIT), ("upstream_archive_sha256", UPSTREAM),
                          ("rust_toolchain", TOOLCHAIN), (SLICES[slice_name], digest)):
        if fields.get(key) != expected:
            raise ValueError(f"{key} mismatch")
    if not fields.get("patch", "").startswith("disable-api-forced-exit-and-split-dns"):
        raise ValueError("required patch flag missing")
    if require_connected_udp and not fields.get("patch","").endswith("-connected-udp"):
        raise ValueError("connected UDP patch flag missing")
    return digest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("framework", type=Path)
    parser.add_argument("slice", choices=SLICES)
    parser.add_argument("--require-connected-udp",action="store_true")
    args = parser.parse_args()
    try:
        print("VERIFIED_LOCAL_RUST_" + args.slice + "_SHA256_" + verify(args.framework, args.slice, require_connected_udp=args.require_connected_udp))
    except (ValueError, OSError) as error:
        print("REJECTED_LOCAL_RUST_ARTIFACT:", str(error))
        raise SystemExit(1)
