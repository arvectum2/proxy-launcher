# -*- coding: utf-8 -*-
"""Production candidate backend for Windows per-application exclusions.

The public Windows path must not depend on an Arvectum-owned kernel driver.
This module describes the user-mode contract for the pinned, pre-built
WinDivert dependency.  It performs no driver installation or packet mutation.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
import hashlib
import json
import ntpath
import os
import re
from typing import Iterable, Mapping, Tuple

from routing_rules import ApplicationIdentity

WINDIVERT_VERSION = "2.2.2"
WINDIVERT_RELEASE_TAG = "v2.2.2"
WINDIVERT_ARCHIVE_NAME = "WinDivert-2.2.2-A.zip"
WINDIVERT_ARCHIVE_SHA256 = (
    "63cb41763bb4b20f600b6de04e991a9c2be73279e317d4d82f237b150c5f3f15"
)
WINDIVERT_X64_DLL_SHA256 = (
    "c1e060ee19444a259b2162f8af0f3fe8c4428a1c6f694dce20de194ac8d7d9a2"
)
WINDIVERT_X64_DRIVER_SHA256 = (
    "8da085332782708d8767bcace5327a6ec7283c17cfb85e40b03cd2323a90ddc2"
)
WINDIVERT_LICENSE_SHA256 = (
    "14a0cb5214d536e4fdae6aa3f5696f981eeda106cd026e9794bba489ee79d628"
)
WINDIVERT_HEADER_SHA256 = (
    "5017a1768c1592fd664c0c2d3d2d30f81fad4ab98d322b1914c6f0a33fcacdf9"
)
WINDIVERT_X64_LIB_SHA256 = (
    "c5678d544eb0121a189d1139f54e0c67854dc64d1c897111a27ef2e52cb38eb3"
)
WINDIVERT_DRIVER_FILENAME = "WinDivert64.sys"
WINDIVERT_DLL_FILENAME = "WinDivert.dll"
WINDIVERT_LICENSE_FILENAME = "WinDivert-LICENSE"
WINDIVERT_DRIVER_SIGNER_THUMBPRINT = "043589F75FCE2795E7F2CC3E526D46784D5DDAB3"

_DRIVE_ABSOLUTE = re.compile(r"^[a-zA-Z]:\\")
UNC_PREFIX = "\\\\"


class WindowsWinDivertError(RuntimeError):
    pass


@dataclass(frozen=True)
class WinDivertApplicationPlan:
    rule_id: str
    application_stable_id: str
    executable_path: str
    local_proxy_port: int
    def to_dict(self) -> Mapping[str, object]:
        return asdict(self)


def _sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_windows_executable_path(path: str) -> str:
    """Return a deterministic case-insensitive absolute Windows path."""
    raw = str(path or "").strip().replace("/", "\\")
    if not raw:
        raise WindowsWinDivertError("Windows executable path is empty")
    normalized = ntpath.normpath(raw)
    if not (_DRIVE_ABSOLUTE.match(normalized) or normalized.startswith(UNC_PREFIX)):
        raise WindowsWinDivertError("Windows executable path must be absolute")
    if normalized.endswith("\\") or ntpath.basename(normalized) in {"", ".", ".."}:
        raise WindowsWinDivertError("Windows executable path is invalid")
    return ntpath.normcase(normalized)


def windows_executable_path_sha256(path: str) -> str:
    normalized = normalize_windows_executable_path(path)
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def _validate_port(value: int, label: str) -> int:
    if isinstance(value, bool):
        raise WindowsWinDivertError(f"{label} must be an integer")
    try:
        port = int(value)
    except (TypeError, ValueError) as exc:
        raise WindowsWinDivertError(f"{label} must be an integer") from exc
    if port <= 0 or port > 65535:
        raise WindowsWinDivertError(f"{label} is out of range")
    return port


def compile_windivert_application_plan(
    identities: Iterable[ApplicationIdentity],
    *,
    local_proxy_port: int,
) -> Tuple[WinDivertApplicationPlan, ...]:
    """Compile selected Windows applications for local proxy-port diversion."""
    proxy_port = _validate_port(local_proxy_port, "local proxy port")
    output = {}
    for identity in identities:
        if not isinstance(identity, ApplicationIdentity):
            raise TypeError("ApplicationIdentity required")
        if identity.platform != "windows" or not identity.executable_path:
            raise WindowsWinDivertError(
                "WinDivert backend requires executable-backed Windows identities"
            )
        executable = normalize_windows_executable_path(identity.executable_path)
        stable_id = identity.stable_id
        output[stable_id] = WinDivertApplicationPlan(
            rule_id="app-exclusion-" + hashlib.sha256(
                stable_id.encode("utf-8")
            ).hexdigest()[:16],
            application_stable_id=stable_id,
            executable_path=executable,
            local_proxy_port=proxy_port,
        )
    return tuple(output[key] for key in sorted(output))


def canonical_windivert_plan_json(
    plans: Iterable[WinDivertApplicationPlan],
) -> str:
    items = tuple(plans)
    if not items:
        raise WindowsWinDivertError("WinDivert routing plan is empty")
    payload = {
        "backend": "windivert",
        "schema": "arvectum.proxy.windows-windivert-plan.v1",
        "applications": [item.to_dict() for item in items],
    }
    return json.dumps(payload, sort_keys=True, separators=(",", ":"))


def build_windivert_socket_filter(local_proxy_port: int) -> str:
    port = _validate_port(local_proxy_port, "local proxy port")
    return (
        "loopback and tcp and remotePort == "
        f"{port} and (event == CONNECT or event == CLOSE)"
    )


def build_windivert_network_filter(
    local_proxy_port: int,
    direct_listener_port: int,
) -> str:
    proxy_port = _validate_port(local_proxy_port, "local proxy port")
    direct_port = _validate_port(direct_listener_port, "direct listener port")
    if proxy_port == direct_port:
        raise WindowsWinDivertError(
            "local proxy and direct listener ports must differ"
        )
    return (
        "loopback and tcp and ("
        f"tcp.DstPort == {proxy_port} or tcp.SrcPort == {direct_port}"
        ")"
    )


def verify_windivert_bundle(
    root: str,
    *,
    driver_signature_status: str | None = None,
    driver_signer_thumbprint: str | None = None,
) -> Mapping[str, object]:
    """Verify the exact pinned x64 files before a build/runtime may trust them."""
    base = os.path.abspath(str(root or ""))
    expected = {
        WINDIVERT_DLL_FILENAME: WINDIVERT_X64_DLL_SHA256,
        WINDIVERT_DRIVER_FILENAME: WINDIVERT_X64_DRIVER_SHA256,
        WINDIVERT_LICENSE_FILENAME: WINDIVERT_LICENSE_SHA256,
    }
    hashes = {}
    for name, digest in expected.items():
        path = os.path.join(base, name)
        if not os.path.isfile(path):
            return {
                "ready": False,
                "state": "files_missing",
                "reason": f"required WinDivert file is absent: {name}",
            }
        actual = _sha256(path)
        hashes[name] = actual
        if actual.lower() != digest.lower():
            return {
                "ready": False,
                "state": "hash_mismatch",
                "reason": f"pinned WinDivert file hash mismatch: {name}",
                "file": name,
                "actual_sha256": actual,
                "expected_sha256": digest,
            }

    signature = str(driver_signature_status or "").strip()
    if signature.lower() != "valid":
        return {
            "ready": False,
            "state": "driver_signature_invalid",
            "reason": "WinDivert kernel driver Authenticode status is not Valid",
            "signature_status": signature or None,
        }
    thumbprint = re.sub(
        r"[^0-9A-Fa-f]",
        "",
        str(driver_signer_thumbprint or ""),
    ).upper()
    if thumbprint != WINDIVERT_DRIVER_SIGNER_THUMBPRINT:
        return {
            "ready": False,
            "state": "driver_signer_mismatch",
            "reason": "WinDivert kernel driver signer thumbprint is not pinned",
            "driver_signer_thumbprint": thumbprint or None,
            "expected_driver_signer_thumbprint":
                WINDIVERT_DRIVER_SIGNER_THUMBPRINT,
        }
    return {
        "ready": True,
        "state": "verified",
        "reason": "exact pinned WinDivert 2.2.2 x64 bundle verified",
        "version": WINDIVERT_VERSION,
        "hashes": hashes,
        "driver_signature_status": signature,
        "driver_signer_thumbprint": thumbprint,
    }
