# -*- coding: utf-8 -*-
"""Per-user LaunchAgent ownership for macOS autostart ownership."""
import os
import plistlib
import posixpath
import tempfile
from typing import Optional

LABEL = "ru.arvectum.proxylauncher"
DEFAULT_EXECUTABLE = "/Applications/Arvectum Proxy Launcher.app/Contents/MacOS/Arvectum Proxy Launcher"


def default_launchagent_path(home: Optional[str] = None) -> str:
    root = os.path.abspath(os.path.expanduser(home or "~"))
    return os.path.join(root, "Library", "LaunchAgents", LABEL + ".plist")


def _normalize_macos_executable(executable: str) -> str:
    """Normalize a LaunchAgent executable using macOS/POSIX semantics on every CI host."""
    value = str(executable or "").strip()
    if not value.startswith("/"):
        raise ValueError("LaunchAgent executable must be an absolute macOS path")
    return posixpath.normpath(value)


def launchagent_payload(executable: str = DEFAULT_EXECUTABLE):
    executable = _normalize_macos_executable(executable)
    return {
        "Label": LABEL,
        "ProgramArguments": [executable],
        "RunAtLoad": True,
        "KeepAlive": False,
        "ProcessType": "Interactive",
        "LimitLoadToSessionType": "Aqua",
    }


def is_autostart_enabled(path: Optional[str] = None) -> bool:
    target = path or default_launchagent_path()
    try:
        with open(target, "rb") as stream:
            payload = plistlib.load(stream)
    except (FileNotFoundError, OSError, plistlib.InvalidFileException):
        return False
    return payload.get("Label") == LABEL and payload.get("ProgramArguments") == [DEFAULT_EXECUTABLE] and payload.get("RunAtLoad") is True


def enable_autostart(path: Optional[str] = None, executable: str = DEFAULT_EXECUTABLE) -> str:
    target = os.path.abspath(os.path.expanduser(path or default_launchagent_path()))
    if os.path.exists(target) and not is_autostart_enabled(target):
        raise RuntimeError(
            "LaunchAgent path is occupied by a configuration not owned by Arvectum"
        )
    parent = os.path.dirname(target)
    os.makedirs(parent, mode=0o700, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=LABEL + ".", suffix=".tmp", dir=parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            plistlib.dump(launchagent_payload(executable), stream, fmt=plistlib.FMT_XML, sort_keys=True)
            stream.flush(); os.fsync(stream.fileno())
        os.chmod(temp, 0o600)
        os.replace(temp, target)
    finally:
        if os.path.exists(temp): os.unlink(temp)
    return target


def disable_autostart(path: Optional[str] = None) -> bool:
    target = os.path.abspath(os.path.expanduser(path or default_launchagent_path()))
    if not os.path.exists(target):
        return False
    if not is_autostart_enabled(target):
        return False
    os.remove(target)
    return True
