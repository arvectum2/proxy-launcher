#!/usr/bin/env python3
"""Compare two APL-LNX-010 NetworkManager proxy snapshots."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def _load(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema") != 1 or payload.get("collector") != "APL-LNX-010":
        raise ValueError(f"unsupported snapshot: {path}")
    return payload


def _comparable(payload: dict) -> dict:
    result = {}
    for connection in payload.get("connections", []):
        identity = connection.get("identity_sha256")
        if not identity or identity in result:
            raise ValueError("invalid or duplicate connection identity")
        result[identity] = {
            "type": connection.get("type"),
            "proxy": connection.get("proxy"),
        }
    return result


def compare(before: dict, after: dict) -> tuple[bool, list[str]]:
    left = _comparable(before)
    right = _comparable(after)
    failures: list[str] = []
    if set(left) != set(right):
        missing = sorted(set(left) - set(right))
        added = sorted(set(right) - set(left))
        if missing:
            failures.append(f"baseline connections missing after rollback: {len(missing)}")
        if added:
            failures.append(f"new active connections after rollback: {len(added)}")
    for identity in sorted(set(left) & set(right)):
        if left[identity] != right[identity]:
            failures.append(f"proxy state differs for connection {identity[:12]}")
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
        print("NetworkManager proxy state matches the captured baseline.")
        return 0
    print("RESULT: FAIL")
    for failure in failures:
        print(f"- {failure}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
