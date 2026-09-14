#!/usr/bin/env python3
"""Collect privacy-preserving, read-only NetworkManager proxy state for APL-REG-001C-REDOS."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from typing import Iterable

IGNORED_TYPES = {"vpn", "loopback"}


def _digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _run_nmcli(arguments: Iterable[str]) -> str:
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    completed = subprocess.run(
        ["nmcli", *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        timeout=15,
        env=env,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"nmcli failed: {detail or 'unknown error'}")
    return completed.stdout.rstrip("\n")


def _split_terse(line: str) -> tuple[str, ...]:
    fields: list[str] = []
    current: list[str] = []
    escaped = False
    for char in line:
        if escaped:
            current.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == ":":
            fields.append("".join(current))
            current = []
        else:
            current.append(char)
    if escaped:
        current.append("\\")
    fields.append("".join(current))
    return tuple(fields)


def _value(uuid: str, property_name: str) -> str:
    return _run_nmcli(
        ["--escape", "no", "--get-values", property_name, "connection", "show", "uuid", uuid]
    )


def collect_state() -> dict:
    rows = _run_nmcli(
        ["--terse", "--escape", "yes", "--fields", "UUID,TYPE,DEVICE", "connection", "show", "--active"]
    )
    connections = []
    for line in rows.splitlines():
        if not line.strip():
            continue
        fields = _split_terse(line)
        if len(fields) != 3:
            raise RuntimeError("unexpected nmcli active-connection row")
        uuid, connection_type, device = (field.strip() for field in fields)
        connection_type = connection_type.lower()
        if not uuid or connection_type in IGNORED_TYPES:
            continue
        method = _value(uuid, "proxy.method").strip().lower()
        browser = _value(uuid, "proxy.browser-only").strip().lower()
        pac_url = _value(uuid, "proxy.pac-url")
        pac_script = _value(uuid, "proxy.pac-script")
        connections.append(
            {
                "identity_sha256": _digest(uuid),
                "type": connection_type,
                "device": device,
                "proxy": {
                    "method": method,
                    "browser_only": browser in {"yes", "true", "on", "1"},
                    "pac_url_present": bool(pac_url),
                    "pac_url_sha256": _digest(pac_url),
                    "pac_script_present": bool(pac_script),
                    "pac_script_sha256": _digest(pac_script),
                },
            }
        )
    connections.sort(key=lambda item: item["identity_sha256"])
    return {
        "schema": 1,
        "collector": "APL-REG-001C-REDOS",
        "privacy": "raw connection UUIDs and PAC contents are SHA-256 digested",
        "connection_count": len(connections),
        "connections": connections,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    payload = collect_state()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
