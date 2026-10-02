# -*- coding: utf-8 -*-
"""Fail-closed readiness for the production WinDivert Windows backend."""
from __future__ import annotations

import ctypes
import hashlib
import json
import os
import re
import subprocess
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
PORTABLE_BUILD_MANIFEST_FILENAME = "build_manifest.json"
PORTABLE_BUNDLE_DIRNAME = "WINDOWS_WINDIVERT"
PORTABLE_HELPER_FILENAME = "windivert_service_helper.ps1"
PORTABLE_STACK_MANIFEST_FILENAME = "windivert-stack-build.json"
PORTABLE_DEPENDENCY_MANIFEST_FILENAME = "windivert-dependency.json"

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


def portable_application_dir() -> str:
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))


def portable_bundle_root() -> str:
    return os.path.join(portable_application_dir(), PORTABLE_BUNDLE_DIRNAME)


def _read_json_file(path: str):
    try:
        with open(path, "r", encoding="utf-8-sig") as stream:
            return json.load(stream)
    except (OSError, ValueError, TypeError):
        return None


def portable_windivert_bootstrap_readiness() -> Mapping[str, object]:
    if not _is_windows():
        return _fail(
            "not_windows",
            "WinDivert portable bootstrap is only available on Windows",
            portable_bootstrap_available=False,
        )
    if not getattr(sys, "frozen", False):
        return _fail(
            "not_frozen",
            "WinDivert portable bootstrap is only exposed by packaged builds",
            portable_bootstrap_available=False,
        )

    app_dir = portable_application_dir()
    build_manifest_path = os.path.join(
        app_dir, PORTABLE_BUILD_MANIFEST_FILENAME
    )
    build_manifest = _read_json_file(build_manifest_path)
    if not isinstance(build_manifest, Mapping):
        return _fail(
            "portable_manifest_missing",
            "Portable build manifest is absent or unreadable",
            portable_bootstrap_available=False,
        )

    source_commit = str(
        build_manifest.get("source_commit") or ""
    ).lower()
    if (
        not re.fullmatch(r"[0-9a-f]{40}", source_commit)
        or build_manifest.get("format") != "portable"
        or not bool(build_manifest.get("windivert_stack_enabled"))
    ):
        return _fail(
            "portable_manifest_invalid",
            "Portable WinDivert build identity is invalid",
            portable_bootstrap_available=False,
        )

    bundle = portable_bundle_root()
    helper = os.path.join(bundle, PORTABLE_HELPER_FILENAME)
    stack_manifest_path = os.path.join(
        bundle, PORTABLE_STACK_MANIFEST_FILENAME
    )
    dependency_manifest_path = os.path.join(
        bundle, PORTABLE_DEPENDENCY_MANIFEST_FILENAME
    )
    required_paths = (
        helper,
        stack_manifest_path,
        dependency_manifest_path,
        os.path.join(bundle, SERVICE_FILENAME),
        os.path.join(bundle, WINDIVERT_DLL_FILENAME),
        os.path.join(bundle, WINDIVERT_DRIVER_FILENAME),
        os.path.join(bundle, WINDIVERT_LICENSE_FILENAME),
    )
    if not all(os.path.isfile(path) for path in required_paths):
        return _fail(
            "portable_payload_missing",
            "Portable WinDivert bootstrap payload is incomplete",
            portable_bootstrap_available=False,
        )

    stack_manifest = _read_json_file(stack_manifest_path)
    dependency = _read_json_file(dependency_manifest_path)
    if not isinstance(stack_manifest, Mapping) or not isinstance(
        dependency, Mapping
    ):
        return _fail(
            "portable_payload_invalid",
            "Portable WinDivert payload manifests are unreadable",
            portable_bootstrap_available=False,
        )

    service = stack_manifest.get("service")
    if (
        stack_manifest.get("schema")
        != "arvectum.proxy.windows-windivert-build.v1"
        or str(stack_manifest.get("source_commit") or "").lower()
        != source_commit
        or stack_manifest.get("version") != WINDIVERT_VERSION
        or not isinstance(service, Mapping)
        or service.get("filename") != SERVICE_FILENAME
    ):
        return _fail(
            "portable_payload_invalid",
            "Portable WinDivert stack manifest identity is invalid",
            portable_bootstrap_available=False,
        )

    helper_hash = _sha256(helper)
    dependency_hash = _sha256(dependency_manifest_path)
    service_hash = _sha256(os.path.join(bundle, SERVICE_FILENAME))
    if (
        helper_hash
        != str(
            build_manifest.get("windivert_service_helper_sha256") or ""
        ).lower()
        or dependency_hash
        != str(
            build_manifest.get(
                "windivert_dependency_manifest_sha256"
            ) or ""
        ).lower()
        or service_hash
        != str(
            build_manifest.get("windivert_service_sha256") or ""
        ).lower()
        or service_hash
        != str(service.get("sha256") or "").lower()
        or dependency_hash
        != str(
            stack_manifest.get("dependency_manifest_sha256") or ""
        ).lower()
    ):
        return _fail(
            "portable_payload_hash_mismatch",
            "Portable WinDivert bootstrap payload hash mismatch",
            portable_bootstrap_available=False,
        )

    if (
        str(dependency.get("version") or "") != WINDIVERT_VERSION
        or str(
            dependency.get("files", {}).get(
                WINDIVERT_DRIVER_FILENAME, ""
            )
        ).lower()
        != WINDIVERT_X64_DRIVER_SHA256
        or str(
            dependency.get("files", {}).get(
                WINDIVERT_DLL_FILENAME, ""
            )
        ).lower()
        != WINDIVERT_X64_DLL_SHA256
        or str(
            dependency.get("files", {}).get(
                WINDIVERT_LICENSE_FILENAME, ""
            )
        ).lower()
        != WINDIVERT_LICENSE_SHA256
        or str(
            dependency.get("driver_signer_thumbprint") or ""
        ).upper()
        != WINDIVERT_DRIVER_SIGNER_THUMBPRINT
    ):
        return _fail(
            "portable_dependency_mismatch",
            "Portable WinDivert dependency identity is not pinned",
            portable_bootstrap_available=False,
        )

    actual_dependency_hashes = {
        WINDIVERT_DRIVER_FILENAME: _sha256(
            os.path.join(bundle, WINDIVERT_DRIVER_FILENAME)
        ),
        WINDIVERT_DLL_FILENAME: _sha256(
            os.path.join(bundle, WINDIVERT_DLL_FILENAME)
        ),
        WINDIVERT_LICENSE_FILENAME: _sha256(
            os.path.join(bundle, WINDIVERT_LICENSE_FILENAME)
        ),
    }
    expected_dependency_hashes = {
        WINDIVERT_DRIVER_FILENAME: WINDIVERT_X64_DRIVER_SHA256,
        WINDIVERT_DLL_FILENAME: WINDIVERT_X64_DLL_SHA256,
        WINDIVERT_LICENSE_FILENAME: WINDIVERT_LICENSE_SHA256,
    }
    if actual_dependency_hashes != expected_dependency_hashes:
        return _fail(
            "portable_dependency_hash_mismatch",
            "Portable WinDivert dependency bytes do not match pinned hashes",
            portable_bootstrap_available=False,
        )

    return {
        "ready": False,
        "state": "portable_bootstrap_ready",
        "reason": (
            "Portable WinDivert routing payload is verified and can be "
            "installed with one Windows administrator consent"
        ),
        "backend": "windivert",
        "version": WINDIVERT_VERSION,
        "portable_bootstrap_available": True,
        "source_commit": source_commit,
        "bundle_root": bundle,
        "helper_path": helper,
    }


def _run_elevated_powershell(parameters, *, timeout_ms=120000) -> int:
    if not _is_windows():
        raise RuntimeError("Windows elevation is unavailable")
    shell32 = ctypes.WinDLL("shell32.dll", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32.dll", use_last_error=True)

    class SHELLEXECUTEINFOW(ctypes.Structure):
        _fields_ = [
            ("cbSize", ctypes.c_uint32),
            ("fMask", ctypes.c_ulong),
            ("hwnd", ctypes.c_void_p),
            ("lpVerb", ctypes.c_wchar_p),
            ("lpFile", ctypes.c_wchar_p),
            ("lpParameters", ctypes.c_wchar_p),
            ("lpDirectory", ctypes.c_wchar_p),
            ("nShow", ctypes.c_int),
            ("hInstApp", ctypes.c_void_p),
            ("lpIDList", ctypes.c_void_p),
            ("lpClass", ctypes.c_wchar_p),
            ("hkeyClass", ctypes.c_void_p),
            ("dwHotKey", ctypes.c_uint32),
            ("hIcon", ctypes.c_void_p),
            ("hProcess", ctypes.c_void_p),
        ]

    execute = shell32.ShellExecuteExW
    execute.argtypes = [ctypes.POINTER(SHELLEXECUTEINFOW)]
    execute.restype = ctypes.c_int
    wait = kernel32.WaitForSingleObject
    wait.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    wait.restype = ctypes.c_uint32
    get_exit = kernel32.GetExitCodeProcess
    get_exit.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_uint32),
    ]
    get_exit.restype = ctypes.c_int
    close = kernel32.CloseHandle
    close.argtypes = [ctypes.c_void_p]
    close.restype = ctypes.c_int

    powershell = os.path.join(
        os.environ.get("SystemRoot") or r"C:\Windows",
        "System32",
        "WindowsPowerShell",
        "v1.0",
        "powershell.exe",
    )
    info = SHELLEXECUTEINFOW()
    info.cbSize = ctypes.sizeof(info)
    info.fMask = 0x00000040
    info.lpVerb = "runas"
    info.lpFile = powershell
    info.lpParameters = subprocess.list2cmdline(list(parameters))
    info.nShow = 0
    if not execute(ctypes.byref(info)):
        raise ctypes.WinError(ctypes.get_last_error())
    if not info.hProcess:
        raise RuntimeError("Elevated WinDivert bootstrap process was not created")
    try:
        status = wait(info.hProcess, int(timeout_ms))
        if status == 0x00000102:
            raise TimeoutError("Elevated WinDivert bootstrap timed out")
        exit_code = ctypes.c_uint32()
        if not get_exit(info.hProcess, ctypes.byref(exit_code)):
            raise ctypes.WinError(ctypes.get_last_error())
        return int(exit_code.value)
    finally:
        close(info.hProcess)


def bootstrap_windows_windivert_stack() -> Mapping[str, object]:
    installed = windows_windivert_stack_readiness()
    if installed.get("ready"):
        return installed

    portable = portable_windivert_bootstrap_readiness()
    if not portable.get("portable_bootstrap_available"):
        return portable

    helper = str(portable["helper_path"])
    bundle = str(portable["bundle_root"])
    source_commit = str(portable["source_commit"])
    exit_code = _run_elevated_powershell(
        [
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            helper,
            "-Action",
            "Install",
            "-SourceDirectory",
            bundle,
            "-SourceCommit",
            source_commit,
        ]
    )
    if exit_code != 0:
        return _fail(
            "portable_bootstrap_failed",
            "Windows declined or failed the WinDivert routing installation",
            portable_bootstrap_available=True,
            exit_code=exit_code,
        )

    result = windows_windivert_stack_readiness()
    if not result.get("ready"):
        return _fail(
            "portable_bootstrap_incomplete",
            str(result.get("reason") or "WinDivert installation did not become ready"),
            portable_bootstrap_available=True,
            readiness=dict(result),
        )
    return result


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
