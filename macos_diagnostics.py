# -*- coding: utf-8 -*-
"""Privacy-bounded macOS diagnostics/support bundle for macOS diagnostics."""
import json
import os
import subprocess
import tempfile
import zipfile
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Sequence

from macos_networksetup_preflight import detect_macos_network_preflight
from macos_runtime import detect_macos_runtime


def _run_readonly(args: Sequence[str]) -> Dict[str, Any]:
    try:
        result = subprocess.run(list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False, timeout=10)
        return {"returncode": int(result.returncode), "stdout": str(result.stdout or "")[:12000], "stderr": str(result.stderr or "")[:4000]}
    except Exception as exc:
        return {"returncode": 127, "stdout": "", "stderr": type(exc).__name__}


def collect_macos_diagnostics(*, runtime=None, preflight=None, command_runner: Callable[[Sequence[str]], Dict[str, Any]] = _run_readonly) -> Dict[str, Any]:
    runtime = runtime or detect_macos_runtime()
    preflight = preflight or detect_macos_network_preflight(runtime=runtime)
    commands = {}
    for name, args in (
        ("sw_vers", ["/usr/bin/sw_vers"]),
        ("network_services", [runtime.networksetup_path, "-listallnetworkservices"] if runtime.networksetup_path else []),
    ):
        commands[name] = command_runner(args) if args else {"returncode":127,"stdout":"","stderr":"unavailable"}
    return {
        "schema_version": 1,
        "collected_at_utc": datetime.now(timezone.utc).isoformat(),
        "platform": "macos",
        "runtime": {
            "product_version": runtime.product_version,
            "architecture": runtime.architecture,
            "networksetup_available": bool(runtime.networksetup_path),
            "launchctl_available": bool(runtime.launchctl_path),
            "hdiutil_available": bool(runtime.hdiutil_path),
        },
        "preflight": {
            "status": getattr(preflight.status, "value", str(preflight.status)),
            "enabled_service_count": len(preflight.enabled_services),
            "readable_service_count": len(preflight.readable_services),
            "reasons": list(preflight.reasons),
        },
        "commands": commands,
        "privacy": {
            "excluded": ["proxy credentials", "environment dump", "browser history", "home directory listing", "rollback file contents"],
            "note": "Service names and operating-system metadata may be present; credentials and rollback payloads are not collected.",
        },
    }


def write_macos_support_bundle(output_path: str, *, report=None) -> str:
    report = report or collect_macos_diagnostics()
    target = os.path.abspath(os.path.expanduser(output_path))
    os.makedirs(os.path.dirname(target), exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix="arvectum-macos-support-", suffix=".zip", dir=os.path.dirname(target))
    os.close(fd)
    try:
        with zipfile.ZipFile(temp, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("diagnostics.json", json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
            archive.writestr("README.txt", "Arvectum Proxy Launcher macOS support bundle. Review diagnostics.json before sharing. No proxy credentials or rollback payload contents are intentionally collected.\n")
        os.replace(temp, target)
    finally:
        if os.path.exists(temp): os.unlink(temp)
    return target