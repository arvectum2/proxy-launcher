"""Canonical Windows Recovery Run ownership for Arvectum Proxy Launcher.

Owns strict recovery/autostart command classification and HKCU Run-entry mutation. Ownership is proven by exact command/path structure, foreign same-named values are preserved, and process-inspection failures are fail-closed.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from types import ModuleType


_RECOVERY_RUN_VALUE = "ArvectumProxyLauncherRecovery"
_RECOVERY_CURRENT_OWNED = "CURRENT_OWNED"
_RECOVERY_LEGACY_ARVECTUM = "LEGACY_ARVECTUM"
_RECOVERY_FOREIGN = "FOREIGN"
_RECOVERY_MISSING = "MISSING"

_CORE: ModuleType | None = None


def configure(core: ModuleType) -> None:
    """Bind the canonical composition module used for runtime collaborators."""
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("Recovery autostart ownership is not configured")
    return _CORE


def _self_start_command():
    """Return the exact command representing the current launcher start path."""
    core = _core()
    if getattr(sys, "frozen", False):
        return '"%s" --start' % core.managed_executable()
    return '"%s" "%s" --start' % (
        sys.executable,
        os.path.realpath(core.__file__),
    )


def _normalize_command(value):
    """Normalize quoting/whitespace only; never use substring ownership tests."""
    return " ".join(str(value or "").replace("'", '"').split()).strip().lower()


def _known_legacy_recovery_dirs():
    """Return exact current/historical directories that prove Arvectum ownership."""
    core = _core()
    home = os.path.expanduser("~")
    local = os.environ.get("LOCALAPPDATA") or os.path.join(home, "AppData", "Local")
    candidates = [
        core.install_dir(),
        core.stable_app_dir(),
        core.historical_documents_app_dir(),
        os.path.join(local, "ArvectumProxyLauncher"),
        os.path.join(local, "Arvectum", "ProxyLauncher"),
    ]
    return {os.path.normcase(os.path.realpath(path)) for path in candidates}


def _recovery_command_target(command):
    """Return only an explicit quoted executable/batch target plus arguments."""
    match = re.match(r'^\s*"([^"]+)"(?:\s+(.*))?\s*$', str(command or ""))
    if not match:
        return None, ""
    return os.path.realpath(match.group(1)), (match.group(2) or "").strip()


def _is_temporary_arvectum_start(command):
    """Recognize only the exact launcher --start command in a temporary root."""
    core = _core()
    target, args = core._recovery_command_target(command)
    return bool(
        target
        and os.path.basename(target).lower() == core._LAUNCHER_EXE_NAME.lower()
        and core._normalize_command(args) == "--start"
        and core.is_temporary_path(target)
    )


def _is_proven_legacy_arvectum_start(command):
    """Strictly identify legacy Arvectum start entries, never a foreign command."""
    core = _core()
    target, args = core._recovery_command_target(command)
    if not target or os.path.basename(target).lower() != core._LAUNCHER_EXE_NAME.lower():
        return False
    if core._normalize_command(args) != "--start":
        return False
    if core._is_temporary_arvectum_start(command):
        return True
    parent = os.path.normcase(os.path.realpath(os.path.dirname(target)))
    if parent in core._known_legacy_recovery_dirs():
        return True
    return any(
        part.lower().startswith("arvectum-proxy-launcher-windows-")
        for part in os.path.normpath(target).split(os.sep)
    )


def _delete_run_value(name):
    """Delete one HKCU Run value; absence is already a safe terminal state."""
    core = _core()
    try:
        import winreg

        path = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            path,
            0,
            winreg.KEY_SET_VALUE,
        ) as key:
            winreg.DeleteValue(key, name)
        return True
    except FileNotFoundError:
        return True
    except Exception as exc:
        core._log("Run value delete error for %s: %r" % (name, exc))
        return False


def repair_portable_run_entries():
    """Repair only provably-owned legacy Run entries to the canonical P0 state."""
    core = _core()
    if not core.is_windows():
        return True
    try:
        import winreg

        stable = core.managed_executable()
        if not stable:
            return False
        expected = '"%s" --start' % stable
        path = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, path) as key:
            for name in (core._USER_AUTOSTART_RUN_VALUE, core._RECOVERY_RUN_VALUE):
                try:
                    current, _ = winreg.QueryValueEx(key, name)
                except FileNotFoundError:
                    continue
                if not core._is_proven_legacy_arvectum_start(current):
                    continue
                if name == core._USER_AUTOSTART_RUN_VALUE:
                    winreg.SetValueEx(key, name, 0, winreg.REG_SZ, expected)
                    core._log("legacy user autostart migrated to canonical LocalAppData Programs copy")
                else:
                    winreg.DeleteValue(key, name)
                    core._log("legacy recovery Run value removed; P0 uses one user autostart entry")
        return True
    except Exception as exc:
        core._log("portable Run entry repair failed: %r" % exc)
        return False


def classify_recovery_autostart(command):
    """Classify the shared recovery Run value without heuristic substring checks."""
    core = _core()
    if command is None or not str(command).strip():
        return core._RECOVERY_MISSING
    if core._normalize_command(command) == core._normalize_command(core._self_start_command()):
        return core._RECOVERY_CURRENT_OWNED
    if core._is_proven_legacy_arvectum_start(command):
        return core._RECOVERY_LEGACY_ARVECTUM
    target, args = core._recovery_command_target(command)
    if not target:
        return core._RECOVERY_FOREIGN
    parent = os.path.normcase(os.path.realpath(os.path.dirname(target)))
    name = os.path.basename(target).lower()
    if parent not in core._known_legacy_recovery_dirs():
        return core._RECOVERY_FOREIGN
    if name == "arvectum proxy launcher.exe" and core._normalize_command(args) == "--start":
        return core._RECOVERY_LEGACY_ARVECTUM
    if name == "restore_network.bat" and not args:
        return core._RECOVERY_LEGACY_ARVECTUM
    return core._RECOVERY_FOREIGN


def is_owned_arvectum_start_command(command):
    """Strict ownership predicate shared by recovery and user-autostart UI."""
    core = _core()
    if core._normalize_command(command) == core._normalize_command(core._self_start_command()):
        return True
    if core._is_proven_legacy_arvectum_start(command):
        return True
    target, args = core._recovery_command_target(command)
    if not target or os.path.basename(target).lower() != core._LAUNCHER_EXE_NAME.lower():
        return False
    if core._normalize_command(args) != "--start":
        return False
    return (
        os.path.normcase(os.path.realpath(os.path.dirname(target)))
        in core._known_legacy_recovery_dirs()
    )


def _recovery_legacy_process_active(command):
    """Return whether the exact legacy recovery command may still be executing.

    Any process-inspection failure is fail-closed and therefore treated as
    active, preventing migration/replacement of a potentially live owner.
    """
    core = _core()
    target, _ = core._recovery_command_target(command)
    if not target or not os.path.exists(target):
        return False
    if not core.is_windows():
        return True
    try:
        script = (
            "$p=Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object "
            "{ $_.ExecutablePath -and [IO.Path]::GetFullPath($_.ExecutablePath) -ieq "
            "[IO.Path]::GetFullPath($args[0]) -and $_.CommandLine -eq $args[1] }; "
            "if($p){exit 10}else{exit 0}"
        )
        result = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                script,
                target,
                str(command),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
        return result.returncode != 0
    except Exception as exc:
        core._log("legacy recovery process inspection failed; migration blocked: %r" % exc)
        return True


def _get_recovery_run_value():
    """Read the shared recovery Run value, distinguishing missing from unreadable."""
    core = _core()
    try:
        import winreg

        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            "Software\\Microsoft\\Windows\\CurrentVersion\\Run",
        ) as key:
            return winreg.QueryValueEx(key, core._RECOVERY_RUN_VALUE)[0]
    except FileNotFoundError:
        return None
    except Exception as exc:
        core._log("recovery autostart read error: %r" % exc)
        return False


def _set_recovery_run_value(value):
    """Write the shared recovery Run value through the exact HKCU location."""
    core = _core()
    try:
        import winreg

        with winreg.CreateKey(
            winreg.HKEY_CURRENT_USER,
            "Software\\Microsoft\\Windows\\CurrentVersion\\Run",
        ) as key:
            winreg.SetValueEx(key, core._RECOVERY_RUN_VALUE, 0, winreg.REG_SZ, value)
        return True
    except Exception as exc:
        core._log("recovery autostart write error: %r" % exc)
        return False


def _enable_recovery_autostart():
    core = _core()
    if not core.is_windows():
        return True
    current = core._get_recovery_run_value()
    if current is False:
        core._log("recovery Run state unreadable; P0 continues without recovery autostart")
        return True
    classification = core.classify_recovery_autostart(current)
    if classification == core._RECOVERY_FOREIGN:
        core._log(
            "recovery autostart conflicts with a foreign command; leaving it untouched and continuing without recovery autostart"
        )
        return True
    if classification in (
        core._RECOVERY_LEGACY_ARVECTUM,
        core._RECOVERY_CURRENT_OWNED,
    ):
        return core._delete_run_value(core._RECOVERY_RUN_VALUE)
    return classification == core._RECOVERY_MISSING


def _disable_recovery_autostart():
    """Delete only a current or proven temporary recovery Run value."""
    core = _core()
    if not core.is_windows():
        return True
    try:
        import winreg

        path = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            path,
            0,
            winreg.KEY_QUERY_VALUE | winreg.KEY_SET_VALUE,
        ) as key:
            try:
                current, _ = winreg.QueryValueEx(key, core._RECOVERY_RUN_VALUE)
            except FileNotFoundError:
                return True
            if (
                core._normalize_command(current)
                != core._normalize_command(core._self_start_command())
                and not core._is_temporary_arvectum_start(current)
            ):
                core._log("recovery autostart belongs to another command; leaving it untouched")
                return True
            winreg.DeleteValue(key, core._RECOVERY_RUN_VALUE)
        return True
    except FileNotFoundError:
        return True
    except Exception as exc:
        core._log("recovery autostart disable error: %r" % exc)
        return False


def install_into_core(core: ModuleType) -> ModuleType:
    """Expose canonical recovery-autostart ownership through ``proxy_core``."""
    configure(core)
    core._RECOVERY_RUN_VALUE = _RECOVERY_RUN_VALUE
    core._RECOVERY_CURRENT_OWNED = _RECOVERY_CURRENT_OWNED
    core._RECOVERY_LEGACY_ARVECTUM = _RECOVERY_LEGACY_ARVECTUM
    core._RECOVERY_FOREIGN = _RECOVERY_FOREIGN
    core._RECOVERY_MISSING = _RECOVERY_MISSING
    for name in (
        "_self_start_command",
        "_normalize_command",
        "_known_legacy_recovery_dirs",
        "_recovery_command_target",
        "_is_temporary_arvectum_start",
        "_is_proven_legacy_arvectum_start",
        "_delete_run_value",
        "repair_portable_run_entries",
        "classify_recovery_autostart",
        "is_owned_arvectum_start_command",
        "_recovery_legacy_process_active",
        "_get_recovery_run_value",
        "_set_recovery_run_value",
        "_enable_recovery_autostart",
        "_disable_recovery_autostart",
    ):
        setattr(core, name, globals()[name])
    return core
