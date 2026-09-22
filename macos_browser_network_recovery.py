"""Narrow macOS browser network-session recovery after system resume.

This module deliberately does not touch APL listeners, system proxy settings,
browser main processes, tabs, or renderer processes. It only recycles browser
network-service subprocesses whose ownership can be proven fail-closed.
"""

from __future__ import annotations

import os
import signal
import subprocess
import sys
from types import ModuleType

_CORE: ModuleType | None = None

_PS = "/bin/ps"
_LSOF = "/usr/sbin/lsof"
_CHROME_MAIN = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
_CHROME_NETWORK_TOKEN = "--utility-sub-type=network.mojom.NetworkService"
_WEBKIT_NETWORK_TOKEN = "/com.apple.WebKit.Networking"
_SAFARI_CONTAINER = os.path.expanduser("~/Library/Containers/com.apple.Safari/")


def configure(core: ModuleType) -> None:
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("macOS browser network recovery is not configured")
    return _CORE


def _process_rows():
    try:
        result = subprocess.run(
            [_PS, "-axo", "uid=,pid=,ppid=,command="],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except Exception:
        return []
    if result.returncode != 0:
        return []

    rows = []
    for raw in result.stdout.splitlines():
        parts = raw.strip().split(None, 3)
        if len(parts) != 4:
            continue
        try:
            uid, pid, ppid = map(int, parts[:3])
        except ValueError:
            continue
        rows.append(
            {"uid": uid, "pid": pid, "ppid": ppid, "command": parts[3]}
        )
    return rows


def _pid_uses_safari_container(pid: int) -> bool:
    try:
        result = subprocess.run(
            [_LSOF, "-Fn", "-p", str(int(pid))],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except Exception:
        return False
    if result.returncode != 0:
        return False
    prefix = "n" + _SAFARI_CONTAINER
    return any(line.startswith(prefix) for line in result.stdout.splitlines())


def _browser_network_candidates():
    if sys.platform != "darwin":
        return []

    uid = os.getuid()
    rows = _process_rows()
    by_pid = {row["pid"]: row for row in rows}
    candidates = []

    for row in rows:
        if row["uid"] != uid:
            continue
        command = row["command"]

        if _CHROME_NETWORK_TOKEN in command and "Google Chrome Helper" in command:
            parent = by_pid.get(row["ppid"])
            if (
                parent
                and parent["uid"] == uid
                and parent["command"].startswith(_CHROME_MAIN)
                and "--no-proxy-server" not in parent["command"]
            ):
                candidates.append(("google_chrome", row["pid"]))
            continue

        if (
            _WEBKIT_NETWORK_TOKEN in command
            and _pid_uses_safari_container(row["pid"])
        ):
            candidates.append(("safari", row["pid"]))

    return candidates


def recover_browser_network_services():
    """Recycle only proven Safari/Chrome network services on macOS."""
    core = _core()
    candidates = _browser_network_candidates()
    recovered = []

    core.structured_log(
        "macOS browser network recovery scan",
        event="proxy.resume.browser_network_recovery",
        phase="scan",
        candidate_count=len(candidates),
    )

    for browser, pid in candidates:
        try:
            os.kill(pid, signal.SIGKILL)
        except Exception as exc:
            core.structured_log(
                "macOS browser network service recycle failed",
                level="WARNING",
                event="proxy.resume.browser_network_recovery",
                phase="signal_failed",
                browser=browser,
                pid=pid,
                error_type=type(exc).__name__,
            )
            continue
        recovered.append((browser, pid))
        core.structured_log(
            "macOS browser network service recycled",
            event="proxy.resume.browser_network_recovery",
            phase="signalled",
            browser=browser,
            pid=pid,
        )

    core.structured_log(
        "macOS browser network recovery completed",
        event="proxy.resume.browser_network_recovery",
        phase="completed",
        recycled_count=len(recovered),
    )
    return recovered


def install_into_core(core: ModuleType) -> ModuleType:
    configure(core)
    core.recover_browser_network_services = recover_browser_network_services
    return core
