# -*- coding: utf-8 -*-
"""Fail-closed readiness for the production WinDivert Windows backend."""
from __future__ import annotations

import ctypes
import hashlib
import json
import os
import re
import sys
from typing import Mapping, Optional

from windows_windivert_backend import (
    WINDIVERT_DLL_FILENAME,
    WINDIVERT_DRIVER_FILENAME,
    WINDIVERT_DRIVER_SIGNER_THUMBPRINT,
    WINDIVERT_LICENSE_FILENAME,
    WINDIVERT_LICENSE_SHA256,
    WINDIVERT_VERSION,
    WINDIVERT_X64_DLL_SHA256,
    WINDIVERT_X64_DRIVER_SHA256,
)

SCHEMA = "arvectum.proxy.windows-windivert-stack.v1"
SERVICE_NAME = "ArvectumProxyWinDivertRouting"
SERVICE_FILENAME = "ArvectumProxyWinDivertRoutingService.exe"
MARKER_FILENAME = "windivert-stack.json"

_SERVICE_WIN32_OWN_PROCESS = 0x00000010
_SERVICE_AUTO_START = 0x00000002
_SERVICE_RUNNING = 0x00000004


def _is_windows() -> bool:
    return sys.platform.lower().startswith("win")


def install_root() -> str:
    root = os.environ.get("PROGRAMDATA") or r"C:\ProgramData"
    return os.path.join(
        root, "Arvectum", "ProxyLauncher", "WinDivert"
    )


def marker_path() -> str:
    root = os.environ.get("PROGRAMDATA") or r"C:\ProgramData"
    return os.path.join(
        root, "Arvectum", "ProxyLauncher", MARKER_FILENAME
    )


def current_application_source_commit() -> Optional[str]:
    if not getattr(sys, "frozen", False):
        return None
    manifest_path = os.path.join(
        os.path.dirname(os.path.abspath(sys.executable)),
        "build_manifest.json",
    )
    try:
        with open(manifest_path, "r", encoding="utf-8-sig") as stream:
            payload = json.load(stream)
    except (OSError, ValueError, TypeError):
        return None
    commit = str(payload.get("source_commit") or "").lower()
    return commit if re.fullmatch(r"[0-9a-f]{40}", commit) else None


def _sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _normalize_service_path(value: str) -> str:
    text = str(value or "").strip().strip('"')
    if text.startswith("\\??\\"):
        text = text[4:]
    system_root = os.environ.get("SystemRoot") or r"C:\Windows"
    lower = text.lower()
    if lower.startswith("\\systemroot\\"):
        text = os.path.join(
            system_root, text[len("\\SystemRoot\\"):]
        )
    elif lower.startswith("system32\\"):
        text = os.path.join(system_root, text)
    return os.path.normcase(
        os.path.normpath(os.path.expandvars(text))
    )


def _service_registry_record(
    name: str,
) -> Optional[Mapping[str, object]]:
    if not _is_windows():
        return None
    import winreg

    path = rf"SYSTEM\CurrentControlSet\Services\{name}"
    try:
        with winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE, path
        ) as key:
            image_path, _ = winreg.QueryValueEx(
                key, "ImagePath"
            )
            service_type, _ = winreg.QueryValueEx(
                key, "Type"
            )
            start, _ = winreg.QueryValueEx(key, "Start")
            object_name, _ = winreg.QueryValueEx(
                key, "ObjectName"
            )
            try:
                dependencies, _ = winreg.QueryValueEx(
                    key, "DependOnService"
                )
            except OSError:
                dependencies = ()
    except OSError:
        return None

    if isinstance(dependencies, str):
        dependencies = (dependencies,)
    return {
        "image_path": str(image_path),
        "type": int(service_type),
        "start": int(start),
        "object_name": str(object_name),
        "dependencies": tuple(
            str(item) for item in (dependencies or ())
        ),
    }


def _service_running(name: str) -> bool:
    if not _is_windows():
        return False

    advapi32 = ctypes.WinDLL(
        "Advapi32.dll", use_last_error=True
    )
    open_scm = advapi32.OpenSCManagerW
    open_scm.argtypes = [
        ctypes.c_wchar_p,
        ctypes.c_wchar_p,
        ctypes.c_uint32,
    ]
    open_scm.restype = ctypes.c_void_p
    open_service = advapi32.OpenServiceW
    open_service.argtypes = [
        ctypes.c_void_p,
        ctypes.c_wchar_p,
        ctypes.c_uint32,
    ]
    open_service.restype = ctypes.c_void_p
    close_service = advapi32.CloseServiceHandle
    close_service.argtypes = [ctypes.c_void_p]
    close_service.restype = ctypes.c_int
    query = advapi32.QueryServiceStatusEx
    query.argtypes = [
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_ubyte),
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_uint32),
    ]
    query.restype = ctypes.c_int

    class SERVICE_STATUS_PROCESS(ctypes.Structure):
        _fields_ = [
            ("dwServiceType", ctypes.c_uint32),
            ("dwCurrentState", ctypes.c_uint32),
            ("dwControlsAccepted", ctypes.c_uint32),
            ("dwWin32ExitCode", ctypes.c_uint32),
            ("dwServiceSpecificExitCode", ctypes.c_uint32),
            ("dwCheckPoint", ctypes.c_uint32),
            ("dwWaitHint", ctypes.c_uint32),
            ("dwProcessId", ctypes.c_uint32),
            ("dwServiceFlags", ctypes.c_uint32),
        ]

    scm = open_scm(None, None, 0x0001)
    if not scm:
        return False
    try:
        service = open_service(scm, name, 0x0004)
        if not service:
            return False
        try:
            status = SERVICE_STATUS_PROCESS()
            needed = ctypes.c_uint32()
            ok = query(
                service,
                0,
                ctypes.cast(
                    ctypes.byref(status),
                    ctypes.POINTER(ctypes.c_ubyte),
                ),
                ctypes.sizeof(status),
                ctypes.byref(needed),
            )
            return bool(ok) and (
                status.dwCurrentState == _SERVICE_RUNNING
            )
        finally:
            close_service(service)
    finally:
        close_service(scm)


def _fail(state: str, reason: str, **extra):
    result = {
        "ready": False,
        "state": state,
        "reason": reason,
        "backend": "windivert",
        "version": WINDIVERT_VERSION,
    }
    result.update(extra)
    return result


def windows_windivert_stack_readiness(
    *,
    state_path: Optional[str] = None,
    require_running: bool = True,
) -> Mapping[str, object]:
    if not _is_windows():
        return _fail(
            "not_windows",
            "WinDivert backend can only be verified on Windows",
        )

    path = marker_path() if state_path is None else str(
        state_path
    )
    if not os.path.isfile(path):
        return _fail(
            "not_installed",
            "WinDivert routing stack marker is absent",
        )
    try:
        with open(path, "r", encoding="utf-8") as stream:
            payload = json.load(stream)
    except Exception:
        return _fail(
            "invalid_marker",
            "WinDivert routing stack marker is unreadable",
        )

    expected_root = _normalize_service_path(install_root())
    recorded_root = _normalize_service_path(
        str(payload.get("install_root") or "")
    )
    if (
        payload.get("schema") != SCHEMA
        or payload.get("version") != WINDIVERT_VERSION
        or recorded_root != expected_root
    ):
        return _fail(
            "invalid_marker",
            "WinDivert routing stack marker identity is invalid",
        )

    recorded_source_commit = str(
        payload.get("source_commit") or ""
    ).lower()
    if not re.fullmatch(r"[0-9a-f]{40}", recorded_source_commit):
        return _fail(
            "invalid_marker",
            "WinDivert routing stack source commit is invalid",
        )
    application_source_commit = current_application_source_commit()
    if (
        application_source_commit is not None
        and recorded_source_commit != application_source_commit
    ):
        return _fail(
            "source_commit_mismatch",
            "WinDivert routing stack does not match this application build",
            installed_source_commit=recorded_source_commit,
            application_source_commit=application_source_commit,
        )

    service = payload.get("service")
    dependency = payload.get("dependency")
    if not isinstance(service, Mapping) or not isinstance(
        dependency, Mapping
    ):
        return _fail(
            "invalid_marker",
            "WinDivert routing stack marker is incomplete",
        )

    if (
        service.get("name") != SERVICE_NAME
        or service.get("filename") != SERVICE_FILENAME
        or dependency.get("driver_sha256", "").lower()
        != WINDIVERT_X64_DRIVER_SHA256
        or dependency.get("dll_sha256", "").lower()
        != WINDIVERT_X64_DLL_SHA256
        or dependency.get("license_sha256", "").lower()
        != WINDIVERT_LICENSE_SHA256
        or str(
            dependency.get("driver_signer_thumbprint") or ""
        ).upper()
        != WINDIVERT_DRIVER_SIGNER_THUMBPRINT
    ):
        return _fail(
            "invalid_marker",
            "WinDivert dependency identity is not pinned",
        )

    service_path = os.path.join(
        install_root(), SERVICE_FILENAME
    )
    required = {
        service_path: str(service.get("sha256") or "").lower(),
        os.path.join(
            install_root(), WINDIVERT_DLL_FILENAME
        ): WINDIVERT_X64_DLL_SHA256,
        os.path.join(
            install_root(), WINDIVERT_DRIVER_FILENAME
        ): WINDIVERT_X64_DRIVER_SHA256,
        os.path.join(
            install_root(), WINDIVERT_LICENSE_FILENAME
        ): WINDIVERT_LICENSE_SHA256,
    }
    for file_path, expected_hash in required.items():
        if len(expected_hash) != 64:
            return _fail(
                "invalid_marker",
                "WinDivert stack file hash is invalid",
            )
        if not os.path.isfile(file_path):
            return _fail(
                "files_missing",
                "WinDivert routing stack files are missing",
            )
        try:
            if _sha256(file_path) != expected_hash:
                return _fail(
                    "hash_mismatch",
                    "WinDivert routing stack file hash mismatch",
                    file=file_path,
                )
        except OSError:
            return _fail(
                "files_unreadable",
                "WinDivert routing stack files cannot be verified",
            )

    record = _service_registry_record(SERVICE_NAME)
    if record is None:
        return _fail(
            "service_missing",
            "WinDivert routing service is not registered",
        )
    if (
        _normalize_service_path(record["image_path"])
        != _normalize_service_path(service_path)
        or int(record["type"]) != _SERVICE_WIN32_OWN_PROCESS
        or int(record["start"]) != _SERVICE_AUTO_START
        or record["object_name"].lower()
        not in {"localsystem", ".\\localsystem"}
        or "BFE" not in set(record["dependencies"])
    ):
        return _fail(
            "service_configuration_mismatch",
            "WinDivert routing service configuration is invalid",
        )

    if require_running and not _service_running(SERVICE_NAME):
        return _fail(
            "service_not_running",
            "WinDivert routing service is not running",
        )

    return {
        "ready": True,
        "state": "windivert_ready",
        "reason": (
            "production WinDivert routing service and pinned "
            "dependency are installed and verified"
        ),
        "backend": "windivert",
        "version": WINDIVERT_VERSION,
        "install_root": install_root(),
        "service_name": SERVICE_NAME,
        "driver_signer_thumbprint":
            WINDIVERT_DRIVER_SIGNER_THUMBPRINT,
    }

