"""Canonical Windows system-proxy persistence for Arvectum Proxy Launcher.

Owns WinINET and per-user proxy-environment persistence and mutation. Original user state is captured before mutation, ambiguous rollback evidence is never overwritten, and backup evidence is removed only after successful restore. Recovery Run and orphan-PAC recovery remain explicit separate owners.
"""

from __future__ import annotations

import io
import json
import os
from types import ModuleType
from urllib.parse import urlsplit


_INTERNET_BACKUP_PATH = "proxy_internet_backup.json"
_PROXY_ENV_NAMES = ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY")
_INTERNET_SETTINGS_NAMES = (
    "AutoConfigURL",
    "ProxyEnable",
    "ProxyServer",
    "ProxyOverride",
    "AutoDetect",
)

_CORE: ModuleType | None = None


def configure(core: ModuleType) -> None:
    """Bind the canonical composition module used for runtime collaborators."""
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("Windows system proxy persistence is not configured")
    return _CORE


def _env_backup_path() -> str:
    core = _core()
    return os.path.join(core.runtime_dir(), "proxy_env_backup.json")


def _internet_backup_path() -> str:
    core = _core()
    return os.path.join(core.runtime_dir(), _INTERNET_BACKUP_PATH)


def _read_internet_settings():
    """Read the exact HKCU WinINET values whose ownership must be preserved."""
    core = _core()
    values = {}
    if not core.is_windows():
        return values
    try:
        import winreg

        path = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path) as key:
            for name in _INTERNET_SETTINGS_NAMES:
                try:
                    value, _ = winreg.QueryValueEx(key, name)
                    values[name] = {"exists": True, "value": value}
                except FileNotFoundError:
                    values[name] = {"exists": False, "value": None}
        return values
    except Exception as exc:
        core._log("internet settings read error: %r" % exc)
        return None


def _valid_internet_backup(values) -> bool:
    required = set(_INTERNET_SETTINGS_NAMES)
    return isinstance(values, dict) and required.issubset(values.keys())


def _known_internet_backup_paths():
    """Return current and legacy paths which may prove a WinINET rollback."""
    core = _core()
    paths = [core._internet_backup_path()]
    paths.extend(
        os.path.join(folder, _INTERNET_BACKUP_PATH)
        for folder in core._legacy_state_dirs()
    )
    seen = set()
    unique = []
    for path in paths:
        resolved = os.path.normcase(os.path.realpath(path))
        if resolved in seen:
            continue
        seen.add(resolved)
        unique.append(path)
    return unique


def _valid_internet_backup_at(path) -> bool:
    core = _core()
    try:
        with io.open(path, "r", encoding="utf-8") as stream:
            return core._valid_internet_backup(json.load(stream))
    except Exception:
        return False


def _exact_arvectum_pac_url(value, settings=None) -> bool:
    """Compare a PAC URL structurally; substring similarity never proves ownership."""
    core = _core()
    settings = settings or core.load_settings()
    try:
        actual = urlsplit(str(value or ""))
        expected = urlsplit(core.pac_url(settings))
        return bool(
            actual.scheme.lower() == expected.scheme.lower() == "http"
            and actual.hostname == expected.hostname == "127.0.0.1"
            and actual.port == expected.port
            and actual.path == expected.path
            and not actual.query
            and not actual.fragment
            and actual.username is None
            and actual.password is None
        )
    except (TypeError, ValueError):
        return False


def _state_item_matches(actual, expected) -> bool:
    """Compare one persisted value including absence as part of its identity."""
    actual = actual or {}
    expected = expected or {}
    actual_exists = bool(actual.get("exists"))
    expected_exists = bool(expected.get("exists"))
    if actual_exists != expected_exists:
        return False
    if not actual_exists:
        return True
    return actual.get("value") == expected.get("value")


def _internet_state_is_owned_or_saved(saved, current, settings=None) -> bool:
    """Accept only fields still equal to the saved state or Arvectum-applied state."""
    core = _core()
    if not core._valid_internet_backup(saved) or not core._valid_internet_backup(current):
        return False
    settings = settings or core.load_settings()
    applied = {name: dict(saved[name]) for name in _INTERNET_SETTINGS_NAMES}
    applied["AutoConfigURL"] = {"exists": True, "value": core.pac_url(settings)}
    applied["ProxyEnable"] = {"exists": True, "value": 0}
    return all(
        _state_item_matches(current[name], saved[name])
        or _state_item_matches(current[name], applied[name])
        for name in _INTERNET_SETTINGS_NAMES
    )


def _save_internet_backup() -> bool:
    """Persist original WinINET state before any mutation or fail closed."""
    core = _core()
    path = core._internet_backup_path()
    if os.path.exists(path):
        try:
            with io.open(path, "r", encoding="utf-8") as stream:
                if core._valid_internet_backup(json.load(stream)):
                    return True
        except Exception:
            pass
        core._log("internet settings backup is invalid; refusing to overwrite it")
        return False

    values = core._read_internet_settings()
    if not core._valid_internet_backup(values):
        core._log("internet settings backup aborted: registry snapshot unavailable")
        return False

    temporary = path + ".tmp"
    try:
        with io.open(temporary, "w", encoding="utf-8") as stream:
            json.dump(values, stream, ensure_ascii=False)
            stream.flush()
        os.replace(temporary, path)
        return True
    except Exception as exc:
        core._log("internet settings backup error: %r" % exc)
        try:
            os.remove(temporary)
        except Exception:
            pass
        return False


def _restore_internet_backup() -> bool:
    """Restore only state backed by valid local ownership evidence."""
    core = _core()
    path = core._internet_backup_path()
    try:
        with io.open(path, "r", encoding="utf-8") as stream:
            values = json.load(stream)
    except Exception:
        values = None

    if not core._valid_internet_backup(values):
        # Without a valid local backup there is no proof that current WinINET
        # state belongs to this launcher instance.  Rollback is therefore a
        # non-destructive no-op rather than a guessed network reset.
        core._log(
            "internet settings backup missing/invalid; ownership unverified, "
            "no WinINET values changed"
        )
        return True

    current = core._read_internet_settings()
    if not _internet_state_is_owned_or_saved(values, current):
        core._log(
            "internet settings restore refused: current WinINET state contains "
            "foreign values; backup kept for retry"
        )
        return False

    ok = True
    for name, item in values.items():
        if not isinstance(item, dict) or not item.get("exists"):
            ok = core._reg_del(name) and ok
            continue
        value = item.get("value")
        typ = "REG_DWORD" if name in ("ProxyEnable", "AutoDetect") else "REG_SZ"
        data = str(int(value)) if typ == "REG_DWORD" else str(value)
        ok = core._reg_set(name, data, typ) and ok

    if ok:
        try:
            os.remove(path)
        except Exception as exc:
            core._log("internet settings restored but backup removal failed: %r" % exc)
            return False
    else:
        core._log("internet settings restore incomplete; keeping backup for retry")
    return ok


def _read_user_env(name):
    """Return one user environment value from HKCU Environment."""
    core = _core()
    if not core.is_windows():
        return False, ""
    try:
        import winreg

        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
            value, _ = winreg.QueryValueEx(key, name)
        return True, str(value)
    except FileNotFoundError:
        return False, ""
    except Exception as exc:
        core._log("env read error (%s): %r" % (name, exc))
        return False, ""


def _write_user_env(name, value) -> bool:
    core = _core()
    try:
        import winreg

        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
            winreg.SetValueEx(key, name, 0, winreg.REG_SZ, value)
        return True
    except Exception as exc:
        core._log("env write error (%s): %r" % (name, exc))
        return False


def _delete_user_env(name) -> bool:
    core = _core()
    try:
        import winreg

        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            "Environment",
            0,
            winreg.KEY_SET_VALUE,
        ) as key:
            winreg.DeleteValue(key, name)
        return True
    except FileNotFoundError:
        return True
    except Exception as exc:
        core._log("env delete error (%s): %r" % (name, exc))
        return False


def _broadcast_environment_change() -> None:
    core = _core()
    if not core.is_windows():
        return
    try:
        import ctypes

        ctypes.windll.user32.SendMessageTimeoutW(
            0xFFFF,
            0x001A,
            0,
            "Environment",
            2,
            5000,
            None,
        )
    except Exception as exc:
        core._log("env broadcast error: %r" % exc)


def _combined_no_proxy(backup):
    """Merge original user NO_PROXY with Arvectum defaults and current policy."""
    core = _core()
    direct = []
    existing = str((backup.get("NO_PROXY") or {}).get("value") or "")
    for item in existing.split(",") + list(core.DEFAULT_NO_PROXY) + list(core.load_no_proxy()):
        item = item.strip()
        if item and item not in direct:
            direct.append(item)
    return direct


def _enable_client_proxy_env(port) -> bool:
    """Apply user proxy environment only after a restorable snapshot exists."""
    core = _core()
    backup_path = core._env_backup_path()
    backup = None
    if os.path.exists(backup_path):
        try:
            with io.open(backup_path, "r", encoding="utf-8") as stream:
                candidate = json.load(stream)
            if isinstance(candidate, dict) and all(
                name in candidate for name in _PROXY_ENV_NAMES
            ):
                backup = candidate
        except Exception:
            pass
        if backup is None:
            core._log("env backup is invalid; refusing to overwrite user environment")
            return False
    else:
        backup = {}
        for name in _PROXY_ENV_NAMES:
            exists, value = core._read_user_env(name)
            backup[name] = {"exists": exists, "value": value}
        temporary = backup_path + ".tmp"
        try:
            with io.open(temporary, "w", encoding="utf-8") as stream:
                json.dump(backup, stream, ensure_ascii=False)
                stream.flush()
            os.replace(temporary, backup_path)
        except Exception as exc:
            core._log("env backup error: %r" % exc)
            try:
                os.remove(temporary)
            except Exception:
                pass
            return False

    local_proxy = "http://127.0.0.1:%d" % int(port)
    ok = True
    for name in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"):
        ok = core._write_user_env(name, local_proxy) and ok

    ok = core._write_user_env(
        "NO_PROXY",
        ",".join(core._combined_no_proxy(backup)),
    ) and ok
    if not ok:
        core._log("client proxy environment update incomplete")
        core._disable_client_proxy_env()
        return False

    core._broadcast_environment_change()
    core._log("client proxy environment enabled: %s" % local_proxy)
    return True


def sync_client_no_proxy() -> bool:
    """Synchronize active NO_PROXY while preserving the user's original entries."""
    core = _core()
    if not core.is_windows():
        return True
    backup_path = core._env_backup_path()
    if not os.path.exists(backup_path):
        return True
    try:
        with io.open(backup_path, "r", encoding="utf-8") as stream:
            backup = json.load(stream)
    except Exception as exc:
        core._log("NO_PROXY sync backup read error: %r" % exc)
        return False
    if not isinstance(backup, dict) or not all(
        name in backup for name in _PROXY_ENV_NAMES
    ):
        core._log("NO_PROXY sync aborted: env backup is invalid")
        return False
    if not core._write_user_env(
        "NO_PROXY",
        ",".join(core._combined_no_proxy(backup)),
    ):
        return False
    core._broadcast_environment_change()
    core._log("client NO_PROXY synchronized")
    return True


def _env_state_is_owned_or_saved(backup, port) -> bool:
    """Verify every governed proxy environment value before destructive restore."""
    core = _core()
    if not isinstance(backup, dict) or not all(name in backup for name in _PROXY_ENV_NAMES):
        return False
    local_proxy = "http://127.0.0.1:%d" % int(port)
    applied = {
        "HTTP_PROXY": {"exists": True, "value": local_proxy},
        "HTTPS_PROXY": {"exists": True, "value": local_proxy},
        "ALL_PROXY": {"exists": True, "value": local_proxy},
        "NO_PROXY": {"exists": True, "value": ",".join(core._combined_no_proxy(backup))},
    }
    for name in _PROXY_ENV_NAMES:
        exists, value = core._read_user_env(name)
        current = {"exists": bool(exists), "value": str(value) if exists else ""}
        if not (
            _state_item_matches(current, backup[name])
            or _state_item_matches(current, applied[name])
        ):
            return False
    return True


def _disable_client_proxy_env() -> bool:
    """Restore the exact user proxy environment and retain evidence on failure."""
    core = _core()
    backup_path = core._env_backup_path()
    try:
        with io.open(backup_path, "r", encoding="utf-8") as stream:
            backup = json.load(stream)
    except Exception:
        backup = None
    if not isinstance(backup, dict) or not all(
        name in backup for name in _PROXY_ENV_NAMES
    ):
        return False

    settings = core.load_settings()
    if not _env_state_is_owned_or_saved(
        backup, int(settings.get("local_http_port", 8080))
    ):
        core._log(
            "client proxy environment restore refused: current environment contains "
            "foreign values; backup kept for retry"
        )
        return False

    ok = True
    for name in _PROXY_ENV_NAMES:
        item = backup.get(name) or {}
        if item.get("exists"):
            ok = core._write_user_env(name, str(item.get("value", ""))) and ok
        else:
            ok = core._delete_user_env(name) and ok

    if ok:
        try:
            os.remove(backup_path)
        except Exception as exc:
            core._log(
                "client proxy environment restored but backup removal failed: %r" % exc
            )
            return False
        core._broadcast_environment_change()
        core._log("client proxy environment restored")
    else:
        core._log("client proxy environment restore incomplete; keeping backup for retry")
    return ok


def pac_url(settings) -> str:
    """Build the loopback PAC URL consumed by WinINET and status checks."""
    path = str(settings.get("pac_path", "/proxy.pac") or "/proxy.pac")
    if not path.startswith("/"):
        path = "/" + path
    return "http://127.0.0.1:%d%s" % (
        int(settings.get("local_pac_port", 8082)),
        path,
    )


def _reg_set(name, data, typ) -> bool:
    """Set one owned HKCU Internet Settings value."""
    core = _core()
    if not core.is_windows():
        return False
    try:
        import winreg

        reg_type = winreg.REG_DWORD if typ == "REG_DWORD" else winreg.REG_SZ
        value = int(data) if reg_type == winreg.REG_DWORD else str(data)
        path = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, path) as key:
            winreg.SetValueEx(key, name, 0, reg_type, value)
        return True
    except Exception as exc:
        core._log("registry set error (%s): %r" % (name, exc))
        return False


def _reg_del(name) -> bool:
    """Delete one HKCU Internet Settings value without treating absence as failure."""
    core = _core()
    if not core.is_windows():
        return False
    try:
        import winreg

        path = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            path,
            0,
            winreg.KEY_SET_VALUE,
        ) as key:
            try:
                winreg.DeleteValue(key, name)
            except FileNotFoundError:
                pass
        return True
    except FileNotFoundError:
        return True
    except Exception as exc:
        core._log("registry delete error (%s): %r" % (name, exc))
        return False


def _refresh_internet() -> None:
    """Ask WinINET consumers to re-read the current proxy settings."""
    core = _core()
    if not core.is_windows():
        return
    try:
        import ctypes
        from ctypes import wintypes

        internet_option_settings_changed = 39
        internet_option_refresh = 37
        wininet = ctypes.windll.wininet
        wininet.InternetOpenW.argtypes = [
            wintypes.LPCWSTR,
            wintypes.DWORD,
            wintypes.LPCWSTR,
            wintypes.LPCWSTR,
            wintypes.DWORD,
        ]
        wininet.InternetOpenW.restype = wintypes.HANDLE
        wininet.InternetSetOptionW.argtypes = [
            wintypes.HANDLE,
            wintypes.DWORD,
            wintypes.LPVOID,
            wintypes.DWORD,
        ]
        wininet.InternetSetOptionW.restype = wintypes.BOOL
        wininet.InternetCloseHandle.argtypes = [wintypes.HANDLE]
        wininet.InternetCloseHandle.restype = wintypes.BOOL
        handle = wininet.InternetOpenW("ArvectumProxyLauncher", 0, None, None, 0)
        if handle:
            wininet.InternetSetOptionW(
                handle,
                internet_option_settings_changed,
                None,
                0,
            )
            wininet.InternetSetOptionW(handle, internet_option_refresh, None, 0)
            wininet.InternetCloseHandle(handle)
    except Exception as exc:
        core._log("refresh error: %r" % exc)


def enable_system_proxy() -> bool:
    """Enable the owned PAC/env state only after rollback evidence is durable."""
    core = _core()
    settings = core.load_settings()
    url = core.pac_url(settings)
    if not core.is_windows():
        core._log("system proxy: (non-Windows) %s" % url)
        return True
    if not core._save_internet_backup():
        core._log("system proxy enable aborted: cannot create safe backup")
        return False

    # PAC and the previous manual ProxyServer must not be active in parallel.
    ok = core._reg_set("AutoConfigURL", url, "REG_SZ")
    ok = core._reg_set("ProxyEnable", "0", "REG_DWORD") and ok
    ok = core._enable_client_proxy_env(
        int(settings.get("local_http_port", 8080))
    ) and ok
    # Recovery Run/autostart stays in its existing owner until a later slice.
    ok = core._enable_recovery_autostart() and ok
    if not ok:
        core._restore_internet_backup()
        core._disable_client_proxy_env()
        core._disable_recovery_autostart()
        core._refresh_internet()
        core._log("system proxy enable failed; rolled back")
        return False

    core._refresh_internet()
    core._log("system proxy enabled: %s" % url)
    return True


def disable_system_proxy() -> bool:
    """Restore proven WinINET/env state without guessing foreign ownership."""
    core = _core()
    if not core.is_windows():
        core._log("system proxy: (non-Windows) disabled")
        return True

    was_active = core.system_proxy_enabled()
    valid_backup = core._valid_internet_backup_at(core._internet_backup_path())
    ok = core._restore_internet_backup()
    env_ok = core._disable_client_proxy_env()

    # A recovery Run entry may be removed only once the owned PAC is inactive
    # and all durable rollback evidence is gone. Foreign state can make our PAC
    # inactive while a WinINET backup still requires explicit resolution.
    internet_pending = os.path.exists(core._internet_backup_path())
    env_pending = os.path.exists(core._env_backup_path())
    still_active = core.system_proxy_enabled()
    if not still_active and not internet_pending and not env_pending:
        core._disable_recovery_autostart()

    core._refresh_internet()
    still_active = core.system_proxy_enabled()
    if still_active:
        if valid_backup:
            core._log("system proxy restore incomplete")
        else:
            core._log("system proxy restore skipped: ownership unverified")
    elif was_active or valid_backup:
        core._log("system proxy restored successfully")
    else:
        core._log("system proxy already inactive")
    return (
        ok
        and env_ok
        and not internet_pending
        and not env_pending
        and not still_active
    )


def system_proxy_enabled() -> bool:
    """Return true only for the exact Arvectum loopback PAC configuration."""
    core = _core()
    if not core.is_windows():
        return False
    values = core._read_internet_settings() or {}
    item = values.get("AutoConfigURL") or {}
    return bool(
        item.get("exists") and core._exact_arvectum_pac_url(item.get("value"))
    )


def network_restore_pending() -> bool:
    """Return true while rollback evidence remains for WinINET or proxy env."""
    core = _core()
    if not core.is_windows():
        return False
    return bool(
        os.path.exists(core._internet_backup_path())
        or os.path.exists(core._env_backup_path())
    )


def install_into_core(core: ModuleType) -> ModuleType:
    """Expose canonical Windows persistence seams through ``proxy_core``."""
    configure(core)
    core._INTERNET_BACKUP_PATH = _INTERNET_BACKUP_PATH
    core._PROXY_ENV_NAMES = _PROXY_ENV_NAMES
    for name in (
        "_env_backup_path",
        "_internet_backup_path",
        "_read_internet_settings",
        "_valid_internet_backup",
        "_known_internet_backup_paths",
        "_valid_internet_backup_at",
        "_exact_arvectum_pac_url",
        "_save_internet_backup",
        "_restore_internet_backup",
        "_read_user_env",
        "_write_user_env",
        "_delete_user_env",
        "_broadcast_environment_change",
        "_combined_no_proxy",
        "_enable_client_proxy_env",
        "sync_client_no_proxy",
        "_disable_client_proxy_env",
        "pac_url",
        "_reg_set",
        "_reg_del",
        "_refresh_internet",
        "enable_system_proxy",
        "disable_system_proxy",
        "system_proxy_enabled",
        "network_restore_pending",
    ):
        setattr(core, name, globals()[name])
    return core
