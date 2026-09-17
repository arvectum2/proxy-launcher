# -*- coding: utf-8 -*-
"""Per-user desktop system-proxy integration for Linux desktops.

NetworkManager stores proxy metadata per connection, while graphical browsers
can consume desktop-specific system proxy stores. Astra/Fly uses GSettings;
RED OS 8 Standard Desktop uses KDE/KConfig. Detection remains side-effect free
and selects only the store belonging to the active graphical desktop.
"""

from __future__ import annotations

import ast
from dataclasses import dataclass
import os
import shutil
import subprocess
from typing import Callable, Mapping, Optional


_GSETTINGS_SCHEMA = "org.gnome.system.proxy"
_KDE_DESKTOP_TOKENS = ("kde", "plasma")
_GSETTINGS_DESKTOP_TOKENS = (
    "fly",
    "gnome",
    "unity",
    "cinnamon",
    "budgie",
    "mate",
)


class DesktopProxyError(RuntimeError):
    """Raised when desktop proxy state cannot be read or changed safely."""


@dataclass(frozen=True)
class DesktopProxyState:
    mode: str
    autoconfig_url: str


def _parse_gvariant_string(raw: str) -> str:
    try:
        value = ast.literal_eval(str(raw or "").strip())
    except (SyntaxError, ValueError) as exc:
        raise DesktopProxyError("unexpected GSettings string value") from exc
    if not isinstance(value, str):
        raise DesktopProxyError("unexpected GSettings value type")
    return value


def _gvariant_string(value: str) -> str:
    return repr(str(value))


class GSettingsProxyClient:
    """Small injectable adapter for org.gnome.system.proxy."""

    backend_id = "gsettings"

    def __init__(
        self,
        binary: str = "/usr/bin/gsettings",
        runner: Callable[..., object] = subprocess.run,
        environ: Optional[Mapping[str, str]] = None,
    ) -> None:
        self.binary = str(binary)
        self._runner = runner
        self._environ = dict(os.environ if environ is None else environ)

    def _run(self, *arguments: str) -> str:
        try:
            result = self._runner(
                [self.binary, *arguments],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
                env=self._environ,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            raise DesktopProxyError("gsettings could not be executed") from exc
        if int(getattr(result, "returncode", 1) or 0) != 0:
            detail = str(getattr(result, "stderr", "") or "").strip()
            raise DesktopProxyError(
                "gsettings failed%s" % (": %s" % detail if detail else "")
            )
        return str(getattr(result, "stdout", "") or "").strip()

    def _get_string(self, key: str) -> str:
        return _parse_gvariant_string(self._run("get", _GSETTINGS_SCHEMA, key))

    def _require_writable(self, key: str) -> None:
        writable = self._run("writable", _GSETTINGS_SCHEMA, key).strip().lower()
        if writable != "true":
            raise DesktopProxyError("desktop proxy setting %s is not writable" % key)

    def get_state(self) -> DesktopProxyState:
        mode = self._get_string("mode")
        autoconfig_url = self._get_string("autoconfig-url")
        if mode not in {"none", "manual", "auto"}:
            raise DesktopProxyError("unsupported desktop proxy mode")
        return DesktopProxyState(mode=mode, autoconfig_url=autoconfig_url)

    def set_state(self, state: DesktopProxyState) -> None:
        if not isinstance(state, DesktopProxyState):
            raise DesktopProxyError("invalid desktop proxy state")
        if state.mode not in {"none", "manual", "auto"}:
            raise DesktopProxyError("unsupported desktop proxy mode")
        for key in ("autoconfig-url", "mode"):
            self._require_writable(key)

        # Publish the PAC URL before switching to auto. During restore this also
        # ensures an old auto mode never observes the Arvectum URL after return.
        self._run(
            "set",
            _GSETTINGS_SCHEMA,
            "autoconfig-url",
            _gvariant_string(state.autoconfig_url),
        )
        self._run("set", _GSETTINGS_SCHEMA, "mode", _gvariant_string(state.mode))
        if self.get_state() != state:
            raise DesktopProxyError("desktop proxy verification failed")


def _desktop_identity(environ: Mapping[str, str]) -> str:
    return " ".join(
        str(environ.get(key, "") or "").lower()
        for key in ("XDG_CURRENT_DESKTOP", "DESKTOP_SESSION", "GDMSESSION")
    )


def _desktop_uses_kde(environ: Mapping[str, str]) -> bool:
    desktop = _desktop_identity(environ)
    return any(token in desktop for token in _KDE_DESKTOP_TOKENS)


def _desktop_uses_gsettings(environ: Mapping[str, str]) -> bool:
    desktop = _desktop_identity(environ)
    return any(token in desktop for token in _GSETTINGS_DESKTOP_TOKENS)


def _session_environment(environ: Mapping[str, str]) -> Optional[dict]:
    result = dict(environ)
    address = str(result.get("DBUS_SESSION_BUS_ADDRESS", "") or "").strip()
    if address:
        return result

    runtime = str(result.get("XDG_RUNTIME_DIR", "") or "").strip()
    getuid = getattr(os, "getuid", None)
    if not runtime and getuid is not None:
        candidate = "/run/user/%s" % getuid()
        if os.path.isdir(candidate):
            runtime = candidate
            result["XDG_RUNTIME_DIR"] = candidate
    if runtime:
        bus = os.path.join(runtime, "bus")
        if os.path.exists(bus):
            result["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=%s" % bus
            return result
    return None


def detect_desktop_proxy_client(
    *,
    environ: Optional[Mapping[str, str]] = None,
    which: Callable[[str], Optional[str]] = shutil.which,
    runner: Callable[..., object] = subprocess.run,
) -> Optional[object]:
    """Return the governed desktop proxy adapter for the active session.

    Detection is side-effect free. Unsupported desktops deliberately keep the
    historical NetworkManager-only behavior rather than mutating an unrelated
    desktop configuration store.
    """
    environment = os.environ if environ is None else environ
    session_env = _session_environment(environment)
    if session_env is None:
        return None

    if _desktop_uses_kde(environment):
        read_binary = str(which("kreadconfig5") or "")
        write_binary = str(which("kwriteconfig5") or "")
        signal_binary = str(which("dbus-send") or "")
        if not read_binary or not write_binary or not signal_binary:
            return None
        from linux_kde_proxy import KdeProxyClient

        return KdeProxyClient(
            read_binary=read_binary,
            write_binary=write_binary,
            signal_binary=signal_binary,
            runner=runner,
            environ=session_env,
        )

    if not _desktop_uses_gsettings(environment):
        return None
    binary = str(which("gsettings") or "")
    if not binary:
        return None
    return GSettingsProxyClient(binary=binary, runner=runner, environ=session_env)
