"""Canonical application filesystem for Arvectum Proxy Launcher.

Owns executable, persistent-state and runtime paths, including migration from known historical state locations. Runtime collaborators resolve through the canonical composition module; standard-library dependencies remain local.
"""

from __future__ import annotations

import io
import json
import os
import shutil
import sys
import tempfile
from types import ModuleType
from typing import Any


_CORE: ModuleType | None = None


def configure(core: ModuleType) -> None:
    """Bind the canonical composition module used for runtime collaborators."""
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("application filesystem is not configured")
    return _CORE


def install_dir() -> str:
    """Directory containing this executable/source; never stores mutable state."""
    core = _core()
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.realpath(sys.executable))
    return os.path.dirname(os.path.abspath(core.__file__))


def app_dir() -> str:
    """Compatibility alias for callers needing the executable directory."""
    return _core().install_dir()


def is_windows() -> bool:
    return os.name == "nt"


def data_dir() -> str:
    """Canonical per-user persistent state, shared by every copy of the EXE."""
    core = _core()
    if core.is_windows():
        base = os.environ.get("LOCALAPPDATA") or os.path.join(
            os.path.expanduser("~"), "AppData", "Local"
        )
        return os.path.join(base, "Arvectum", "ProxyLauncher")
    if sys.platform == "darwin":
        return os.path.join(
            os.path.expanduser("~"),
            "Library",
            "Application Support",
            "Arvectum",
            "ProxyLauncher",
        )
    return core.install_dir()


def runtime_dir() -> str:
    return _core().data_dir()


def historical_documents_app_dir() -> str:
    """Pre-0.2.5 Windows executable location retained only for migration."""
    return os.path.join(
        os.path.expanduser("~"), "Documents", "ArvectumProxyLauncher"
    )


def historical_documents_app_exe() -> str:
    core = _core()
    return os.path.join(core.historical_documents_app_dir(), core._LAUNCHER_EXE_NAME)


def stable_app_dir() -> str:
    """Canonical per-user executable location outside protected user folders."""
    home = os.path.expanduser("~")
    local = os.environ.get("LOCALAPPDATA") or os.path.join(home, "AppData", "Local")
    return os.path.join(local, "Programs", "ArvectumProxyLauncher")


def stable_app_exe() -> str:
    core = _core()
    return os.path.join(core.stable_app_dir(), core._LAUNCHER_EXE_NAME)


def _same_path(first: Any, second: Any) -> bool:
    try:
        return os.path.normcase(os.path.realpath(first)) == os.path.normcase(
            os.path.realpath(second)
        )
    except Exception:
        return False


def _temporary_roots() -> list[str]:
    roots = []
    for value in (os.environ.get("TEMP"), os.environ.get("TMP")):
        if value:
            roots.append(value)
    local = os.environ.get("LOCALAPPDATA")
    if local:
        roots.append(os.path.join(local, "Temp"))
    # tempfile avoids shell quoting and remains safe for Cyrillic user names.
    try:
        roots.append(tempfile.gettempdir())
    except Exception:
        pass
    unique = []
    for root in roots:
        resolved = os.path.normcase(os.path.realpath(root))
        if resolved and resolved not in unique:
            unique.append(resolved)
    return unique


def is_temporary_path(path: Any) -> bool:
    """True only when *path* is inside an OS-provided temporary root."""
    core = _core()
    try:
        candidate = os.path.normcase(os.path.realpath(path))
        for root in core._temporary_roots():
            root = os.path.normcase(os.path.realpath(root))
            if os.path.commonpath([candidate, root]) == root:
                return True
    except (TypeError, ValueError):
        pass
    return False


def _legacy_state_dirs() -> list[str]:
    core = _core()
    home = os.path.expanduser("~")
    local = os.environ.get("LOCALAPPDATA") or os.path.join(
        home, "AppData", "Local"
    )
    candidates = [
        core.install_dir(),
        core.historical_documents_app_dir(),
        os.path.join(local, "ArvectumProxyLauncher"),
    ]
    seen = set()
    result = []
    for candidate in candidates:
        resolved = os.path.normcase(os.path.realpath(candidate))
        if resolved in seen:
            continue
        seen.add(resolved)
        result.append(candidate)
    return result


def _copy_state_atomically(src: str, dst: str) -> None:
    temporary = dst + ".migrate.tmp"
    shutil.copyfile(src, temporary)
    with open(temporary, "rb") as stream:
        stream.read(1)
    os.replace(temporary, dst)


def _valid_state_file(name: str, path: str) -> bool:
    if not os.path.isfile(path):
        return False
    if name in (
        "proxy_settings.json",
        "proxy_internet_backup.json",
        "proxy_env_backup.json",
        "proxy_core.pid",
    ):
        try:
            with io.open(path, "r", encoding="utf-8") as stream:
                value = json.load(stream)
            return (
                isinstance(value, dict)
                if name != "proxy_core.pid"
                else bool(value.get("pid"))
            )
        except Exception:
            return False
    return True


def migration_error_path() -> str:
    return os.path.join(_core().data_dir(), "state_migration_conflict.json")


def state_migration_blocked() -> bool:
    core = _core()
    return os.path.exists(core.migration_error_path())


def ensure_state_ready() -> bool:
    """Create stable storage and import validated legacy files once.

    Legacy copies are retained because recovery backups are evidence. When two
    different recovery backups are present the migration fails closed instead
    of guessing which state is authoritative.
    """
    core = _core()
    if core._STATE_READY:
        return not core.state_migration_blocked()
    target = core.data_dir()
    try:
        os.makedirs(target, exist_ok=True)
        for name in core._STATE_FILES:
            existing = os.path.join(target, name)
            sources = []
            for folder in core._legacy_state_dirs():
                candidate = os.path.join(folder, name)
                candidate_resolved = os.path.normcase(os.path.realpath(candidate))
                existing_resolved = os.path.normcase(os.path.realpath(existing))
                if candidate_resolved == existing_resolved:
                    continue
                if core._valid_state_file(name, candidate):
                    sources.append(candidate)
            if not sources or os.path.exists(existing):
                continue
            if name in ("proxy_internet_backup.json", "proxy_env_backup.json"):
                blobs = {open(path, "rb").read() for path in sources}
                if len(blobs) > 1:
                    with io.open(
                        core.migration_error_path(), "w", encoding="utf-8"
                    ) as stream:
                        json.dump(
                            {"file": name, "sources": sources},
                            stream,
                            ensure_ascii=False,
                        )
                    core._STATE_READY = True
                    return False
            core._copy_state_atomically(sources[0], existing)
        core._STATE_READY = True
        return True
    except Exception:
        return False


def settings_path() -> str:
    return os.path.join(_core().data_dir(), "proxy_settings.json")


def settings_backup_path() -> str:
    return os.path.join(_core().data_dir(), "proxy_settings.lastgood.json")


def config_recovery_path() -> str:
    return os.path.join(_core().data_dir(), "config_recovery.json")


def config_quarantine_dir() -> str:
    return os.path.join(_core().data_dir(), "quarantine")


def no_proxy_path() -> str:
    return os.path.join(_core().data_dir(), "no_proxy.txt")


def pid_path() -> str:
    return os.path.join(_core().runtime_dir(), "proxy_core.pid")


def log_path() -> str:
    return os.path.join(_core().runtime_dir(), "proxy_core.log")


def install_into_core(core: ModuleType) -> ModuleType:
    """Expose canonical filesystem seams through the established module object."""
    core.install_dir = install_dir
    core.app_dir = app_dir
    core.is_windows = is_windows
    core.data_dir = data_dir
    core.runtime_dir = runtime_dir
    core.historical_documents_app_dir = historical_documents_app_dir
    core.historical_documents_app_exe = historical_documents_app_exe
    core.stable_app_dir = stable_app_dir
    core.stable_app_exe = stable_app_exe
    core._same_path = _same_path
    core._temporary_roots = _temporary_roots
    core.is_temporary_path = is_temporary_path
    core._legacy_state_dirs = _legacy_state_dirs
    core._copy_state_atomically = _copy_state_atomically
    core._valid_state_file = _valid_state_file
    core.migration_error_path = migration_error_path
    core.state_migration_blocked = state_migration_blocked
    core.ensure_state_ready = ensure_state_ready
    core.settings_path = settings_path
    core.settings_backup_path = settings_backup_path
    core.config_recovery_path = config_recovery_path
    core.config_quarantine_dir = config_quarantine_dir
    core.no_proxy_path = no_proxy_path
    core.pid_path = pid_path
    core.log_path = log_path
    return core
