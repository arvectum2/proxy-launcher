#!/usr/bin/env python3
"""Compare APL-REG-001C RED OS proxy snapshots after rollback/uninstall."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def _load(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema") != 1 or payload.get("collector") != "APL-REG-001C":
        raise ValueError(f"unsupported snapshot: {path}")
    return payload


def _nm_map(payload: dict) -> dict:
    result = {}
    nm = payload.get("networkmanager") or {}
    for connection in nm.get("connections", []):
        identity = connection.get("identity_sha256")
        if not identity or identity in result:
            raise ValueError("invalid or duplicate NetworkManager connection identity")
        result[identity] = {
            "type": connection.get("type"),
            "proxy": connection.get("proxy"),
        }
    return result


def compare(before: dict, after: dict) -> tuple[bool, list[str]]:
    failures: list[str] = []
    left = _nm_map(before)
    right = _nm_map(after)
    if left != right:
        missing = set(left) - set(right)
        added = set(right) - set(left)
        if missing:
            failures.append(f"baseline NetworkManager connections missing: {len(missing)}")
        if added:
            failures.append(f"new active NetworkManager connections: {len(added)}")
        for identity in sorted(set(left) & set(right)):
            if left[identity] != right[identity]:
                failures.append(f"NetworkManager proxy differs for {identity[:12]}")
    if before.get("kde_proxy") != after.get("kde_proxy"):
        failures.append("KDE proxy state differs from baseline")
    if before.get("gsettings_proxy") != after.get("gsettings_proxy"):
        failures.append("GSettings proxy state differs from baseline")
    return not failures, failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args()
    try:
        ok, failures = compare(_load(args.before), _load(args.after))
    except Exception as exc:
        print(f"RESULT: FAIL\nreason={exc}")
        return 2
    if ok:
        print("RESULT: PASS")
        print("NetworkManager, KDE and GSettings proxy state match the captured RED OS baseline.")
        return 0
    print("RESULT: FAIL")
    for failure in failures:
        print(f"- {failure}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
