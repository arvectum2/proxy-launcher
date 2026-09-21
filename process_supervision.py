"""Canonical process supervision for Arvectum Proxy Launcher.

Owns PAC health probing, listener diagnostics, process identity checks, PID persistence, running-state evaluation and ownership-safe termination. Application orchestration and network recovery remain separate owners.
"""

from __future__ import annotations

import io
import json
import os
import socket
import subprocess
import sys
from types import ModuleType

_CORE: ModuleType | None = None


def configure(core: ModuleType) -> None:
    """Bind the canonical composition module used for runtime collaborators."""
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("process supervision is not configured")
    return _CORE


def _pac_healthy(settings=None):
    core = _core()
    settings = settings or core.load_settings()
    port = int(settings.get("local_pac_port", 8082))
    path = str(settings.get("pac_path", "/proxy.pac") or "/proxy.pac")
    if not path.startswith("/"):
        path = "/" + path
    try:
        sock = socket.create_connection(("127.0.0.1", port), timeout=1.0)
        request = (
            "GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" % path
        ).encode("ascii")
        sock.sendall(request)
        data = b""
        while len(data) < 65536:
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
        sock.close()
        return (
            b"200 OK" in data
            and b"FindProxyForURL" in data
            and b"127.0.0.1:" in data
        )
    except Exception:
        return False


def proxy_listener_active():
    """Return whether a compatible PAC endpoint is active on localhost.

    Listener health deliberately does not establish instance ownership. Another
    Arvectum installation can expose the same endpoint; callers that require
    ownership must use :func:`is_running`.
    """
    core = _core()
    return core._pac_healthy(core.load_settings())


def _windows_process_creation_time(pid):
    core = _core()
    if not core.is_windows():
        return None
    try:
        import ctypes
        from ctypes import wintypes

        process_query_limited_information = 0x1000
        kernel32 = ctypes.windll.kernel32
        kernel32.OpenProcess.argtypes = [
            wintypes.DWORD,
            wintypes.BOOL,
            wintypes.DWORD,
        ]
        kernel32.OpenProcess.restype = wintypes.HANDLE
        kernel32.GetProcessTimes.argtypes = [
            wintypes.HANDLE,
            ctypes.POINTER(wintypes.FILETIME),
            ctypes.POINTER(wintypes.FILETIME),
            ctypes.POINTER(wintypes.FILETIME),
            ctypes.POINTER(wintypes.FILETIME),
        ]
        kernel32.GetProcessTimes.restype = wintypes.BOOL
        kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel32.CloseHandle.restype = wintypes.BOOL
        handle = kernel32.OpenProcess(
            process_query_limited_information, False, int(pid)
        )
        if not handle:
            return None
        try:
            creation = wintypes.FILETIME()
            exit_time = wintypes.FILETIME()
            kernel = wintypes.FILETIME()
            user = wintypes.FILETIME()
            if not kernel32.GetProcessTimes(
                handle,
                ctypes.byref(creation),
                ctypes.byref(exit_time),
                ctypes.byref(kernel),
                ctypes.byref(user),
            ):
                return None
            return (
                int(creation.dwHighDateTime) << 32
            ) | int(creation.dwLowDateTime)
        finally:
            kernel32.CloseHandle(handle)
    except Exception as exc:
        core._log("process creation time error: %r" % exc)
        return None


def _windows_process_executable_path(pid):
    core = _core()
    if not core.is_windows():
        return None
    try:
        import ctypes
        from ctypes import wintypes

        process_query_limited_information = 0x1000
        handle = ctypes.windll.kernel32.OpenProcess(
            process_query_limited_information, False, int(pid)
        )
        if not handle:
            return None
        try:
            size = wintypes.DWORD(32768)
            buffer = ctypes.create_unicode_buffer(size.value)
            if not ctypes.windll.kernel32.QueryFullProcessImageNameW(
                handle, 0, buffer, ctypes.byref(size)
            ):
                return None
            return os.path.realpath(buffer.value)
        finally:
            ctypes.windll.kernel32.CloseHandle(handle)
    except Exception:
        return None


def _macos_process_executable_path(pid):
    """Return the real executable path for a macOS PID, or None if unprovable."""
    if sys.platform != "darwin":
        return None
    try:
        import ctypes
        libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
        proc_pidpath = libproc.proc_pidpath
        proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        proc_pidpath.restype = ctypes.c_int
        buffer = ctypes.create_string_buffer(4096)
        size = proc_pidpath(int(pid), buffer, len(buffer))
        if size <= 0:
            return None
        return os.path.realpath(buffer.value.decode("utf-8"))
    except Exception:
        return None


def _macos_listener_owner_pid(settings=None):
    """Recover the packaged macOS worker PID from all three owned listeners."""
    core = _core()
    if sys.platform != "darwin" or not getattr(sys, "frozen", False):
        return None
    settings = settings or core.load_settings()
    ports = []
    for key, default in (
        ("local_http_port", 8080),
        ("local_socks_port", 1080),
        ("local_pac_port", 8082),
    ):
        try:
            port = int(settings.get(key, default))
        except (TypeError, ValueError):
            return None
        if port <= 0 or port > 65535:
            return None
        ports.append(port)

    owner_pid = None
    for port in ports:
        try:
            result = subprocess.run(
                [
                    "/usr/sbin/lsof",
                    "-nP",
                    "-t",
                    "-iTCP:%d" % port,
                    "-sTCP:LISTEN",
                ],
                capture_output=True,
                text=True,
                timeout=2,
                check=False,
            )
        except Exception:
            return None
        if result.returncode != 0:
            return None
        pids = {
            int(line.strip())
            for line in result.stdout.splitlines()
            if line.strip().isdigit()
        }
        if len(pids) != 1:
            return None
        current = next(iter(pids))
        if owner_pid is None:
            owner_pid = current
        elif current != owner_pid:
            return None

    if owner_pid is None:
        return None
    actual_path = core._macos_process_executable_path(owner_pid)
    expected_path = os.path.realpath(sys.executable)
    if not actual_path or os.path.realpath(actual_path) != expected_path:
        return None
    return owner_pid


def _write_pid_record(pid, exe_path):
    """Atomically persist an owned process identity."""
    core = _core()
    path = core.pid_path()
    temp_path = "%s.tmp.%s" % (path, os.getpid())
    record = {
        "pid": int(pid),
        "created": core._windows_process_creation_time(int(pid)),
        "exe_path": os.path.realpath(str(exe_path)),
        "identity": os.path.normcase(os.path.realpath(core.install_dir())),
    }
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with io.open(temp_path, "w", encoding="utf-8") as stream:
            json.dump(record, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_path, path)
        return True
    except Exception as exc:
        core._log("pid write error: %r" % exc)
        try:
            os.remove(temp_path)
        except Exception:
            pass
        return False


def _read_pid():
    core = _core()
    try:
        with io.open(core.pid_path(), "r", encoding="utf-8") as stream:
            raw = stream.read().strip()
        try:
            data = json.loads(raw)
        except Exception:
            data = None
        if isinstance(data, dict) and data.get("pid"):
            return {
                "pid": int(data["pid"]),
                "created": data.get("created"),
                "exe_path": data.get("exe_path"),
                "identity": data.get("identity"),
            }
        # Historical PID-only records are intentionally treated as unverified:
        # they cannot safely authorize taskkill after reboot/PID reuse.
        return {"pid": int(raw), "created": None}
    except Exception:
        return None


def is_running():
    """Return True only for the proxy process owned by this app instance."""
    core = _core()
    if not core.proxy_listener_active():
        return False
    record = core._read_pid()
    if core.is_windows():
        if (
            not isinstance(record, dict)
            or not record.get("pid")
            or record.get("created") is None
        ):
            return False
        actual = core._windows_process_creation_time(int(record["pid"]))
        if actual is None or int(actual) != int(record["created"]):
            return False
        recorded_path = record.get("exe_path")
        actual_path = core._windows_process_executable_path(int(record["pid"]))
        return bool(
            recorded_path
            and actual_path
            and os.path.normcase(os.path.realpath(recorded_path))
            == os.path.normcase(os.path.realpath(actual_path))
        )
    if sys.platform == "darwin":
        if isinstance(record, dict) and record.get("pid"):
            recorded_path = record.get("exe_path")
            actual_path = core._macos_process_executable_path(int(record["pid"]))
            if (
                recorded_path
                and actual_path
                and os.path.realpath(recorded_path) == os.path.realpath(actual_path)
            ):
                return True

        recovered_pid = core._macos_listener_owner_pid()
        if recovered_pid is None:
            return False
        actual_path = core._macos_process_executable_path(recovered_pid)
        if not actual_path or not core._write_pid_record(recovered_pid, actual_path):
            return False
        core._log(
            "recovered macOS worker ownership from listeners: pid=%s" % recovered_pid
        )
        return True
    # Historical Linux behavior remains listener-health based until Linux PID
    # ownership receives its own platform-specific identity primitive.
    return True


def _write_pid():
    return _write_pid_record(os.getpid(), sys.executable)


def _remove_pid(expected_pid=None):
    core = _core()
    if expected_pid is not None:
        record = core._read_pid()
        if (
            not isinstance(record, dict)
            or not record.get("pid")
            or int(record["pid"]) != int(expected_pid)
        ):
            return False
    try:
        os.remove(core.pid_path())
        return True
    except FileNotFoundError:
        return True
    except Exception:
        return False


def _kill_pid(record):
    core = _core()
    if not record:
        return False
    pid = int(record.get("pid")) if isinstance(record, dict) else int(record)
    expected_created = record.get("created") if isinstance(record, dict) else None
    try:
        if core.is_windows():
            actual_created = core._windows_process_creation_time(pid)
            if (
                expected_created is None
                or actual_created is None
                or int(expected_created) != int(actual_created)
            ):
                core._log(
                    "refusing unsafe taskkill for pid=%s: "
                    "process identity mismatch/unverified" % pid
                )
                return False
            result = subprocess.run(
                ["taskkill", "/PID", str(pid), "/F"],
                capture_output=True,
                text=True,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            if result.returncode != 0:
                core._log(
                    "taskkill failed for pid=%s: %s"
                    % (pid, (result.stderr or result.stdout).strip())
                )
                return False
            return True
        if sys.platform == "darwin":
            if not isinstance(record, dict) or not record.get("exe_path"):
                core._log(
                    "refusing unsafe macOS kill for pid=%s: executable identity missing"
                    % pid
                )
                return False
            actual_path = core._macos_process_executable_path(pid)
            recorded_path = record.get("exe_path")
            if (
                not actual_path
                or os.path.realpath(str(recorded_path))
                != os.path.realpath(str(actual_path))
            ):
                core._log(
                    "refusing unsafe macOS kill for pid=%s: process identity mismatch"
                    % pid
                )
                return False
        os.kill(pid, 9)
        return True
    except Exception as exc:
        core._log("kill pid error (%s): %r" % (pid, exc))
        return False


def install_into_core(core: ModuleType) -> None:
    """Install canonical process-supervision seams into the core module."""
    configure(core)
    for name in (
        "_pac_healthy",
        "proxy_listener_active",
        "_windows_process_creation_time",
        "_windows_process_executable_path",
        "_macos_process_executable_path",
        "_macos_listener_owner_pid",
        "_write_pid_record",
        "_read_pid",
        "is_running",
        "_write_pid",
        "_remove_pid",
        "_kill_pid",
    ):
        setattr(core, name, globals()[name])
