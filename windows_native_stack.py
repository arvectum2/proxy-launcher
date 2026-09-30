# -*- coding: utf-8 -*-
"""Read-only readiness checks for the installed Windows native routing stack."""
from __future__ import annotations

import ctypes
import hashlib
import json
import os
import sys
from typing import Mapping, Optional

SCHEMA = "arvectum.proxy.windows-native-stack.v1"
PROTOCOL_VERSION = 3
DRIVER_SERVICE_NAME = "ArvectumProxyRoutingCallout"
ROUTING_SERVICE_NAME = "ArvectumProxyRouting"
DRIVER_FILENAME = "ArvectumProxyRoutingCallout.sys"
SERVICE_FILENAME = "ArvectumProxyRoutingService.exe"

_SERVICE_KERNEL_DRIVER = 0x00000001
_SERVICE_WIN32_OWN_PROCESS = 0x00000010
_SERVICE_AUTO_START = 0x00000002
_SERVICE_DEMAND_START = 0x00000003
_SERVICE_RUNNING = 0x00000004


def _is_windows() -> bool:
    return sys.platform.lower().startswith("win")


def native_stack_state_path() -> str:
    root = os.environ.get("PROGRAMDATA") or r"C:\ProgramData"
    return os.path.join(root, "Arvectum", "ProxyLauncher", "native-stack.json")


def _sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _safe_leaf(value: object) -> Optional[str]:
    text = str(value or "")
    if not text or os.path.basename(text) != text or text in {".", ".."}:
        return None
    return text


def _normalized_service_path(value: str) -> str:
    text = str(value or "").strip().strip('"')
    if text.startswith("\\??\\"):
        text = text[4:]
    system_root = os.environ.get("SystemRoot") or r"C:\Windows"
    lower = text.lower()
    if lower.startswith("\\systemroot\\"):
        text = os.path.join(system_root, text[len("\\SystemRoot\\"):])
    elif lower.startswith("system32\\"):
        text = os.path.join(system_root, text)
    return os.path.normcase(os.path.normpath(os.path.expandvars(text)))


def _service_registry_record(name: str) -> Optional[Mapping[str, object]]:
    if not _is_windows():
        return None
    import winreg

    path = rf"SYSTEM\CurrentControlSet\Services\{name}"
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, path) as key:
            image_path, _ = winreg.QueryValueEx(key, "ImagePath")
            service_type, _ = winreg.QueryValueEx(key, "Type")
            start, _ = winreg.QueryValueEx(key, "Start")
    except OSError:
        return None
    return {
        "image_path": str(image_path),
        "type": int(service_type),
        "start": int(start),
    }


def _service_running(name: str) -> bool:
    if not _is_windows():
        return False

    advapi32 = ctypes.WinDLL("Advapi32.dll", use_last_error=True)
    open_scm = advapi32.OpenSCManagerW
    open_scm.argtypes = [ctypes.c_wchar_p, ctypes.c_wchar_p, ctypes.c_uint32]
    open_scm.restype = ctypes.c_void_p
    open_service = advapi32.OpenServiceW
    open_service.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_uint32]
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

    scm = open_scm(None, None, 0x0001)  # SC_MANAGER_CONNECT
    if not scm:
        return False
    try:
        service = open_service(scm, name, 0x0004)  # SERVICE_QUERY_STATUS
        if not service:
            return False
        try:
            status = SERVICE_STATUS_PROCESS()
            needed = ctypes.c_uint32()
            ok = query(
                service,
                0,  # SC_STATUS_PROCESS_INFO
                ctypes.cast(ctypes.byref(status), ctypes.POINTER(ctypes.c_ubyte)),
                ctypes.sizeof(status),
                ctypes.byref(needed),
            )
            return bool(ok) and status.dwCurrentState == _SERVICE_RUNNING
        finally:
            close_service(service)
    finally:
        close_service(scm)


def _fail(state: str, reason: str, **extra) -> Mapping[str, object]:
    payload = {
        "ready": False,
        "state": state,
        "reason": reason,
        "signing_mode": None,
        "protocol_version": None,
    }
    payload.update(extra)
    return payload


def windows_native_stack_readiness(
    *,
    marker_path: Optional[str] = None,
    require_running: bool = True,
) -> Mapping[str, object]:
    """Return fail-closed readiness for the production-installed Windows stack."""
    if not _is_windows():
        return _fail("not_windows", "native Windows stack can only be verified on Windows")

    path = native_stack_state_path() if marker_path is None else str(marker_path)
    if not os.path.isfile(path):
        return _fail("not_installed", "production native stack marker is absent")

    try:
        with open(path, "r", encoding="utf-8") as stream:
            payload = json.load(stream)
    except Exception:
        return _fail("invalid_marker", "production native stack marker is unreadable")

    if not isinstance(payload, Mapping) or payload.get("schema") != SCHEMA:
        return _fail("invalid_marker", "production native stack marker schema is invalid")

    mode = str(payload.get("signing_mode") or "")
    protocol = payload.get("protocol_version")
    if mode != "production":
        return _fail(
            "non_production_stack",
            "installed native stack is not production-signed",
            signing_mode=mode or None,
            protocol_version=protocol,
        )
    if protocol != PROTOCOL_VERSION:
        return _fail(
            "protocol_mismatch",
            "installed native stack protocol does not match this application",
            signing_mode=mode,
            protocol_version=protocol,
        )

    install_root = str(payload.get("install_root") or "")
    driver = payload.get("driver")
    service = payload.get("service")
    if not install_root or not isinstance(driver, Mapping) or not isinstance(service, Mapping):
        return _fail("invalid_marker", "native stack marker is incomplete", signing_mode=mode, protocol_version=protocol)

    driver_name = _safe_leaf(driver.get("filename"))
    service_name = _safe_leaf(service.get("filename"))
    if driver_name != DRIVER_FILENAME or service_name != SERVICE_FILENAME:
        return _fail("invalid_marker", "native stack filenames are invalid", signing_mode=mode, protocol_version=protocol)
    if driver.get("service_name") != DRIVER_SERVICE_NAME or service.get("service_name") != ROUTING_SERVICE_NAME:
        return _fail("invalid_marker", "native stack service identities are invalid", signing_mode=mode, protocol_version=protocol)

    driver_path = _normalized_service_path(str(driver.get("image_path") or ""))
    service_path = _normalized_service_path(
        str(service.get("image_path") or os.path.join(install_root, service_name))
    )
    expected_driver_hash = str(driver.get("sha256") or "").lower()
    expected_service_hash = str(service.get("sha256") or "").lower()
    if len(expected_driver_hash) != 64 or len(expected_service_hash) != 64:
        return _fail("invalid_marker", "native stack hashes are invalid", signing_mode=mode, protocol_version=protocol)
    if not driver_path or not os.path.isabs(driver_path):
        return _fail("invalid_marker", "driver store image path is invalid", signing_mode=mode, protocol_version=protocol)
    if not os.path.isfile(driver_path) or not os.path.isfile(service_path):
        return _fail("files_missing", "native stack files are missing", signing_mode=mode, protocol_version=protocol)
    try:
        if _sha256(driver_path) != expected_driver_hash or _sha256(service_path) != expected_service_hash:
            return _fail("hash_mismatch", "native stack file hash mismatch", signing_mode=mode, protocol_version=protocol)
    except OSError:
        return _fail("files_unreadable", "native stack files cannot be verified", signing_mode=mode, protocol_version=protocol)

    driver_record = _service_registry_record(DRIVER_SERVICE_NAME)
    service_record = _service_registry_record(ROUTING_SERVICE_NAME)
    if driver_record is None or service_record is None:
        return _fail("services_missing", "native routing services are not registered", signing_mode=mode, protocol_version=protocol)

    expected_driver_path = driver_path
    expected_service_path = service_path
    if _normalized_service_path(driver_record["image_path"]) != expected_driver_path:
        return _fail("service_path_mismatch", "kernel driver service path mismatch", signing_mode=mode, protocol_version=protocol)
    if _normalized_service_path(service_record["image_path"]) != expected_service_path:
        return _fail("service_path_mismatch", "routing service path mismatch", signing_mode=mode, protocol_version=protocol)
    if int(driver_record["type"]) != _SERVICE_KERNEL_DRIVER or int(service_record["type"]) != _SERVICE_WIN32_OWN_PROCESS:
        return _fail("service_type_mismatch", "native routing service type mismatch", signing_mode=mode, protocol_version=protocol)
    if int(driver_record["start"]) != _SERVICE_DEMAND_START or int(service_record["start"]) != _SERVICE_AUTO_START:
        return _fail(
            "service_start_mismatch",
            "native routing driver/service start modes are invalid",
            signing_mode=mode,
            protocol_version=protocol,
        )

    if require_running:
        if not _service_running(DRIVER_SERVICE_NAME) or not _service_running(ROUTING_SERVICE_NAME):
            return _fail("services_not_running", "native routing services are not running", signing_mode=mode, protocol_version=protocol)

    return {
        "ready": True,
        "state": "production_ready",
        "reason": "production native routing stack is installed and verified",
        "signing_mode": mode,
        "protocol_version": protocol,
        "install_root": install_root,
        "source_commit": str(payload.get("source_commit") or ""),
        "version": str(payload.get("version") or ""),
    }
