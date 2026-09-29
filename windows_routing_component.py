# -*- coding: utf-8 -*-
"""Windows app-routing privileged component installation helpers."""
from __future__ import annotations

import ctypes
from ctypes import wintypes
import os
import sys
from types import ModuleType
from typing import Optional

SERVICE_EXE = "ArvectumRoutingService.exe"
DRIVER_SYS = "ArvectumProxyRouting.sys"
_CORE: ModuleType | None = None


class WindowsRoutingComponentError(RuntimeError):
    pass


def configure(core: ModuleType) -> None:
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("Windows routing component is not configured")
    return _CORE


def _payload_roots():
    roots = []
    try:
        roots.append(os.path.join(_core().app_dir(), "routing"))
    except Exception:
        pass
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        roots.append(os.path.join(str(meipass), "routing"))
    roots.append(os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "native", "windows-routing", "out", "Release"))
    seen = set()
    for root in roots:
        key = os.path.normcase(os.path.normpath(root))
        if key not in seen:
            seen.add(key)
            yield root


def windows_routing_component_payload_dir() -> Optional[str]:
    for root in _payload_roots():
        if (
            os.path.isfile(os.path.join(root, SERVICE_EXE))
            and os.path.isfile(os.path.join(root, DRIVER_SYS))
        ):
            return root
    return None


def windows_routing_component_payload_available() -> bool:
    return windows_routing_component_payload_dir() is not None


def current_windows_user_sid() -> str:
    if os.name != "nt":
        raise WindowsRoutingComponentError("Windows SID lookup requires Windows")
    advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    TOKEN_QUERY = 0x0008
    TOKEN_USER_CLASS = 1
    token = wintypes.HANDLE()
    if not advapi32.OpenProcessToken(
        kernel32.GetCurrentProcess(), TOKEN_QUERY, ctypes.byref(token)
    ):
        raise WindowsRoutingComponentError("could not open current Windows token")
    try:
        needed = wintypes.DWORD()
        advapi32.GetTokenInformation(
            token, TOKEN_USER_CLASS, None, 0, ctypes.byref(needed))
        if needed.value <= 0:
            raise WindowsRoutingComponentError("could not size current Windows SID")
        buffer = ctypes.create_string_buffer(needed.value)
        if not advapi32.GetTokenInformation(
            token, TOKEN_USER_CLASS, buffer, needed.value, ctypes.byref(needed)
        ):
            raise WindowsRoutingComponentError("could not read current Windows SID")

        class SID_AND_ATTRIBUTES(ctypes.Structure):
            _fields_ = [("Sid", ctypes.c_void_p), ("Attributes", wintypes.DWORD)]

        class TOKEN_USER(ctypes.Structure):
            _fields_ = [("User", SID_AND_ATTRIBUTES)]

        user = ctypes.cast(buffer, ctypes.POINTER(TOKEN_USER)).contents
        string_sid = wintypes.LPWSTR()
        if not advapi32.ConvertSidToStringSidW(
            user.User.Sid, ctypes.byref(string_sid)
        ):
            raise WindowsRoutingComponentError("could not format current Windows SID")
        try:
            value = str(string_sid.value or "").strip()
            if not value.startswith("S-1-"):
                raise WindowsRoutingComponentError("current Windows SID is invalid")
            return value
        finally:
            if string_sid:
                kernel32.LocalFree(string_sid)
    finally:
        kernel32.CloseHandle(token)


def _shell_execute_elevated(executable: str, arguments: str) -> bool:
    if os.name != "nt":
        raise WindowsRoutingComponentError(
            "routing component installation requires Windows")
    shell32 = ctypes.WinDLL("shell32", use_last_error=True)
    shell32.ShellExecuteW.argtypes = [
        wintypes.HWND, wintypes.LPCWSTR, wintypes.LPCWSTR,
        wintypes.LPCWSTR, wintypes.LPCWSTR, ctypes.c_int,
    ]
    shell32.ShellExecuteW.restype = wintypes.HINSTANCE
    result = shell32.ShellExecuteW(
        None, "runas", executable, arguments, os.path.dirname(executable), 1)
    value = ctypes.cast(result, ctypes.c_void_p).value or 0
    return int(value) > 32


def launch_windows_routing_component_install() -> bool:
    root = windows_routing_component_payload_dir()
    if root is None:
        raise WindowsRoutingComponentError(
            "Windows application-routing component is missing from this build")
    executable = os.path.join(root, SERVICE_EXE)
    sid = current_windows_user_sid()
    if not _shell_execute_elevated(
        executable, '--install --owner-sid "%s"' % sid
    ):
        raise WindowsRoutingComponentError(
            "Windows refused or cancelled the routing component installation")
    return True


def launch_windows_routing_component_uninstall() -> bool:
    root = windows_routing_component_payload_dir()
    if root is None:
        raise WindowsRoutingComponentError(
            "Windows application-routing component is missing from this build")
    executable = os.path.join(root, SERVICE_EXE)
    if not _shell_execute_elevated(executable, "--uninstall"):
        raise WindowsRoutingComponentError(
            "Windows refused or cancelled the routing component removal")
    return True


def install_into_core(core: ModuleType) -> ModuleType:
    core.WindowsRoutingComponentError = WindowsRoutingComponentError
    core.windows_routing_component_payload_dir = windows_routing_component_payload_dir
    core.windows_routing_component_payload_available = windows_routing_component_payload_available
    core.current_windows_user_sid = current_windows_user_sid
    core.launch_windows_routing_component_install = launch_windows_routing_component_install
    core.launch_windows_routing_component_uninstall = launch_windows_routing_component_uninstall
    return core
