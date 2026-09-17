# -*- coding: utf-8 -*-
"""KDE/KConfig system-proxy integration for RED OS and compatible Linux desktops."""

from __future__ import annotations

import os
import subprocess
from typing import Callable, Mapping, Optional

from linux_desktop_proxy import DesktopProxyError, DesktopProxyState


_KDE_PROXY_GROUP = "Proxy Settings"
_KDE_CONFIG_FILE = "kioslaverc"
_KDE_MODE_TO_TYPE = {"none": "0", "manual": "1", "auto": "2"}
_KDE_TYPE_TO_MODE = {value: key for key, value in _KDE_MODE_TO_TYPE.items()}


class KdeProxyClient:
    """Minimal KConfig adapter owning only PAC URL and proxy mode keys."""

    backend_id = "kde"

    def __init__(
        self,
        read_binary: str = "/usr/bin/kreadconfig5",
        write_binary: str = "/usr/bin/kwriteconfig5",
        signal_binary: str = "/usr/bin/dbus-send",
        runner: Callable[..., object] = subprocess.run,
        environ: Optional[Mapping[str, str]] = None,
    ) -> None:
        self.read_binary = str(read_binary)
        self.write_binary = str(write_binary)
        self.signal_binary = str(signal_binary)
        self._runner = runner
        self._environ = dict(os.environ if environ is None else environ)

    def _run(self, argv: list[str]) -> str:
        try:
            result = self._runner(
                argv,
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
                env=self._environ,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            raise DesktopProxyError("KDE proxy tool could not be executed") from exc
        if int(getattr(result, "returncode", 1) or 0) != 0:
            detail = str(getattr(result, "stderr", "") or "").strip()
            raise DesktopProxyError(
                "KDE proxy tool failed%s" % (": %s" % detail if detail else "")
            )
        return str(getattr(result, "stdout", "") or "").strip()

    def _read_key(self, key: str) -> str:
        return self._run(
            [
                self.read_binary,
                "--file",
                _KDE_CONFIG_FILE,
                "--group",
                _KDE_PROXY_GROUP,
                "--key",
                key,
            ]
        )

    def _write_key(self, key: str, value: str) -> None:
        self._run(
            [
                self.write_binary,
                "--file",
                _KDE_CONFIG_FILE,
                "--group",
                _KDE_PROXY_GROUP,
                "--key",
                key,
                str(value),
            ]
        )

    def _notify_kio(self) -> None:
        # KIO consumers cache kioslaverc. Emitting the standard reparse signal
        # is user-session scoped and changes no additional configuration state.
        self._run(
            [
                self.signal_binary,
                "--session",
                "--type=signal",
                "/KIO/Scheduler",
                "org.kde.KIO.Scheduler.reparseSlaveConfiguration",
                "string:",
            ]
        )

    def get_state(self) -> DesktopProxyState:
        proxy_type = self._read_key("ProxyType").strip() or "0"
        mode = _KDE_TYPE_TO_MODE.get(proxy_type)
        if mode is None:
            # ProxyType 3 (WPAD) and 4 (environment) cannot be represented by
            # the cross-desktop rollback state, so fail closed before mutation.
            raise DesktopProxyError("unsupported KDE proxy mode")
        return DesktopProxyState(
            mode=mode,
            autoconfig_url=self._read_key("Proxy Config Script"),
        )

    def set_state(self, state: DesktopProxyState) -> None:
        if not isinstance(state, DesktopProxyState):
            raise DesktopProxyError("invalid desktop proxy state")
        proxy_type = _KDE_MODE_TO_TYPE.get(state.mode)
        if proxy_type is None:
            raise DesktopProxyError("unsupported KDE proxy mode")

        # Like the GSettings backend, write the PAC URL before selecting auto.
        # Manual proxy and NoProxyFor keys are intentionally never touched.
        self._write_key("Proxy Config Script", state.autoconfig_url)
        self._write_key("ProxyType", proxy_type)
        self._notify_kio()
        if self.get_state() != state:
            raise DesktopProxyError("KDE desktop proxy verification failed")
