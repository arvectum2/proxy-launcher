"""Canonical application runtime orchestration for Arvectum Proxy Launcher.

Owns top-level state bootstrap and CLI lifecycle orchestration. Filesystem, transport, process supervision, system-proxy mutation and recovery remain explicit owners and are resolved through the canonical composition module.
"""

from __future__ import annotations

import os
import shutil
import sys
import time
from types import ModuleType

_CORE: ModuleType | None = None

MACOS_RESUME_POLL_SECONDS = 1.0
MACOS_RESUME_GAP_SECONDS = 5.0
MACOS_RESUME_SETTLE_SECONDS = 2.0


def configure(core: ModuleType) -> None:
    """Bind the canonical composition module used for runtime collaborators."""
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("application runtime is not configured")
    return _CORE


def _ensure_local_files():
    """Initialize canonical state and copy bundled defaults into it."""
    core = _core()
    if not core.ensure_state_ready():
        return False
    if not getattr(sys, "frozen", False) or not hasattr(sys, "_MEIPASS"):
        return True
    for name in ("no_proxy.txt", "proxy_settings.json"):
        target = os.path.join(core.data_dir(), name)
        if not os.path.exists(target):
            source = os.path.join(sys._MEIPASS, name)
            try:
                if os.path.exists(source):
                    shutil.copyfile(source, target)
            except Exception as exc:
                core._log("ensure files error: %r" % exc)
                return False
    return True



def _run_proxy_loop(proxy):
    """Wait for shutdown and refresh an owned macOS route after long suspension gaps."""
    if sys.platform != "darwin":
        while not proxy._stop.wait(3600):
            pass
        return

    core = _core()
    last_wall = time.time()
    while not proxy._stop.wait(MACOS_RESUME_POLL_SECONDS):
        now_wall = time.time()
        gap = max(0.0, now_wall - last_wall)
        last_wall = now_wall
        if gap < MACOS_RESUME_GAP_SECONDS:
            continue

        core.structured_log(
            "macOS worker heartbeat gap detected",
            event="proxy.resume.wall_gap_refresh",
            phase="detected",
            gap_seconds=round(gap, 3),
            settle_seconds=MACOS_RESUME_SETTLE_SECONDS,
        )
        if proxy._stop.wait(MACOS_RESUME_SETTLE_SECONDS):
            return

        refreshed = core.refresh_system_proxy()
        core.structured_log(
            (
                "macOS owned direct proxy route reasserted after heartbeat gap"
                if refreshed
                else "macOS owned direct proxy route refresh failed after heartbeat gap"
            ),
            level="INFO" if refreshed else "WARNING",
            event="proxy.resume.wall_gap_refresh",
            phase="completed",
            gap_seconds=round(gap, 3),
            refreshed=bool(refreshed),
        )
        last_wall = time.time()

def _cmd_start():
    core = _core()
    settings = core.load_settings()
    configured = any(
        (upstream.get("host") or "").strip()
        for upstream in settings.get("upstream") or []
    )
    if not configured:
        core._log("start aborted: no upstream proxy configured")
        print("upstream proxy is not configured")
        return 2
    if core.is_running():
        core._log("already running, enabling system proxy")
        return 0 if core.enable_system_proxy() else 1

    proxy = core.ProxyCore(settings)
    ok, message = proxy.start()
    if not ok:
        core._log("start failed: %s" % message)
        print(message)
        return 1

    core._write_pid()
    if not core.enable_system_proxy():
        proxy.stop()
        core._remove_pid(os.getpid())
        print("failed to enable system proxy; network settings rolled back")
        return 1

    print("proxy started")
    try:
        _run_proxy_loop(proxy)
    except KeyboardInterrupt:
        pass
    finally:
        proxy.stop()
        core._remove_pid(os.getpid())
    return 0


def _cmd_stop():
    core = _core()
    if not core.system_proxy_disable_preflight():
        print(
            "proxy stop refused: saved network state depends on an unavailable "
            "local PAC service; restore that service and retry"
        )
        return 1
    record = core._read_pid()
    if core.is_running():
        record = core._read_pid() or record
    killed = core._kill_pid(record)
    still_running = core.is_running()
    if killed or not still_running:
        core._remove_pid()
    network_ok = core.disable_system_proxy()
    still_running = core.is_running()
    pending = core.network_restore_pending()
    if still_running:
        print("proxy process is still running; network proxy was disabled where possible")
        return 1
    if not network_ok or pending:
        print("proxy stopped, but network settings restore is incomplete; retry --rollback")
        return 1
    print("proxy stopped; network settings restored")
    return 0


def _cmd_rollback():
    """Emergency rollback independent of a running GUI or proxy process."""
    core = _core()
    if not core.system_proxy_disable_preflight():
        print(
            "rollback refused: saved network state depends on an unavailable "
            "local PAC service; restore that service and retry"
        )
        return 1
    record = core._read_pid()
    if core.is_running():
        record = core._read_pid() or record
    killed = core._kill_pid(record)
    still_running = core.is_running()
    if killed or not still_running:
        core._remove_pid()
    network_ok = core.disable_system_proxy()
    still_running = core.is_running()
    pending = core.network_restore_pending()
    if still_running:
        print("network proxy was disabled where possible, but proxy process is still running")
        return 1
    if not network_ok or pending:
        print("network settings restore is incomplete; recovery files were kept for retry")
        return 1
    print("network settings restored")
    return 0


def _cmd_status():
    core = _core()
    settings = core.load_settings()
    if core.is_running():
        print(
            "RUNNING (http=127.0.0.1:%d socks=127.0.0.1:%d pac=%s)"
            % (
                settings["local_http_port"],
                settings["local_socks_port"],
                core.pac_url(settings),
            )
        )
        print(
            "system proxy: %s"
            % ("ENABLED" if core.system_proxy_enabled() else "disabled")
        )
        print("exceptions: %d domains" % len(core.load_no_proxy()))
    else:
        print("STOPPED")


def main():
    core = _core()
    action = (
        sys.argv[1][2:]
        if len(sys.argv) > 1 and sys.argv[1].startswith("--")
        else ("start" if len(sys.argv) == 1 else None)
    )

    # A portable --start must never register its temporary extraction path in
    # HKCU Run. Re-execute from the stable copy before mutating any network
    # settings or recovery state.
    if action == "start" and core.handoff_to_stable_copy(sys.argv[1:]):
        print("opened permanent launcher copy")
        return 0
    if not core._ensure_local_files():
        print("state initialization failed")
        return 1

    core.repair_portable_run_entries()
    if action == "start":
        return core._cmd_start()
    if action == "stop":
        return core._cmd_stop()
    if action == "status":
        core._cmd_status()
        return 0
    if action == "rollback":
        return core._cmd_rollback()
    print("usage: proxy_core.py --start | --stop | --status | --rollback")
    return 2


def install_into_core(core: ModuleType) -> ModuleType:
    """Expose canonical application-runtime seams through ``proxy_core``."""
    configure(core)
    for name in (
        "_ensure_local_files",
        "_run_proxy_loop",
        "_cmd_start",
        "_cmd_stop",
        "_cmd_rollback",
        "_cmd_status",
        "main",
    ):
        setattr(core, name, globals()[name])
    return core
