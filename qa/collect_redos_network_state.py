#!/usr/bin/env python3
"""Collect read-only RED OS NetworkManager + KDE/GSettings proxy state."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from collect_astra_network_state import collect_state as collect_networkmanager_state


def _digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _run(argv: list[str]) -> str:
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    completed = subprocess.run(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        timeout=10,
        env=env,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError("command failed: %s" % (detail or argv[0]))
    return completed.stdout.rstrip("\n")


def _kde_state() -> dict | None:
    binary = shutil.which("kreadconfig5")
    desktop = " ".join(
        os.environ.get(key, "").lower()
        for key in ("XDG_CURRENT_DESKTOP", "DESKTOP_SESSION", "GDMSESSION")
    )
    if not binary or not any(token in desktop for token in ("kde", "plasma")):
        return None
    keys = (
        "ProxyType",
        "Proxy Config Script",
        "NoProxyFor",
        "ReversedException",
        "httpProxy",
        "httpsProxy",
        "ftpProxy",
        "socksProxy",
    )
    result = {}
    for key in keys:
        value = _run(
            [binary, "--file", "kioslaverc", "--group", "Proxy Settings", "--key", key]
        )
        if key in {"ProxyType", "ReversedException"}:
            result[key] = value
        else:
            result[key] = {
                "present": bool(value),
                "sha256": _digest(value),
            }
    return result


def _gsettings_state() -> dict | None:
    binary = shutil.which("gsettings")
    if not binary:
        return None
    try:
        mode = _run([binary, "get", "org.gnome.system.proxy", "mode"])
        pac = _run([binary, "get", "org.gnome.system.proxy", "autoconfig-url"])
    except RuntimeError:
        return None
    return {
        "mode_raw": mode,
        "autoconfig_url_raw_sha256": _digest(pac),
    }


def collect_state() -> dict:
    networkmanager = collect_networkmanager_state()
    return {
        "schema": 1,
        "collector": "APL-REG-001C",
        "privacy": "connection UUIDs, PAC values, bypass/manual proxy values are SHA-256 digested",
        "networkmanager": {
            "connection_count": networkmanager["connection_count"],
            "connections": networkmanager["connections"],
        },
        "kde_proxy": _kde_state(),
        "gsettings_proxy": _gsettings_state(),
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
