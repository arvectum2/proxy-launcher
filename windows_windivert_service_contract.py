# -*- coding: utf-8 -*-
"""Bounded control contract for the privileged WinDivert routing service."""
from __future__ import annotations

from dataclasses import asdict, dataclass
import json
import re
import uuid
from typing import Iterable, Mapping, Tuple

from routing_ownership import OwnedRoutingResource, RESOURCE_PREFIX
from windows_windivert_backend import (
    WinDivertApplicationPlan,
    windows_executable_path_sha256,
)

PROTOCOL_VERSION = 1
MAX_APPLICATIONS = 128
PIPE_NAME = r"\\.\pipe\Arvectum.ProxyLauncher.WinDivertRouting"
_SHA256 = re.compile(r"^[0-9a-f]{64}$")

OWNED_RESOURCES: Tuple[OwnedRoutingResource, ...] = (
    OwnedRoutingResource(
        "windivert_session",
        RESOURCE_PREFIX + "WinDivert.SocketTracker",
    ),
    OwnedRoutingResource(
        "windivert_session",
        RESOURCE_PREFIX + "WinDivert.NetworkTranslator",
    ),
)


class WindowsWinDivertContractError(RuntimeError):
    pass
@dataclass(frozen=True)
class ServiceApplication:
    rule_id: str
    application_path_sha256: str
    local_proxy_port: int

    def to_dict(self) -> Mapping[str, object]:
        return asdict(self)


def _validate_session_id(value: str) -> str:
    try:
        return str(uuid.UUID(str(value)))
    except Exception as exc:
        raise WindowsWinDivertContractError(
            "invalid WinDivert routing session id"
        ) from exc


def _validate_digest(value: str) -> str:
    digest = str(value or "").lower()
    if not _SHA256.fullmatch(digest):
        raise WindowsWinDivertContractError(
            "invalid WinDivert routing plan digest"
        )
    return digest


def _validate_port(value: int, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise WindowsWinDivertContractError(f"{label} must be an integer")
    if value <= 0 or value > 65535:
        raise WindowsWinDivertContractError(f"{label} is out of range")
    return value


def _service_application(
    plan: WinDivertApplicationPlan,
) -> ServiceApplication:
    if not isinstance(plan, WinDivertApplicationPlan):
        raise TypeError("WinDivertApplicationPlan required")
    path_hash = windows_executable_path_sha256(plan.executable_path)
    port = _validate_port(plan.local_proxy_port, "local proxy port")
    rule_id = str(plan.rule_id or "").strip()
    stable_id = str(plan.application_stable_id or "").strip()
    if not rule_id or not stable_id:
        raise WindowsWinDivertContractError(
            "WinDivert application identity is incomplete"
        )
    return ServiceApplication(
        rule_id=rule_id,
        application_path_sha256=path_hash,
        local_proxy_port=port,
    )


def canonical_plan_json(
    plans: Iterable[WinDivertApplicationPlan],
) -> str:
    applications = tuple(_service_application(item) for item in plans)
    if not applications:
        raise WindowsWinDivertContractError("WinDivert routing plan is empty")
    if len(applications) > MAX_APPLICATIONS:
        raise WindowsWinDivertContractError(
            "WinDivert routing plan exceeds application limit"
        )
    proxy_ports = {item.local_proxy_port for item in applications}
    if len(proxy_ports) != 1:
        raise WindowsWinDivertContractError(
            "WinDivert routing plan must use one local proxy port"
        )
    payload = {
        "protocol_version": PROTOCOL_VERSION,
        "backend": "windivert",
        "applications": [item.to_dict() for item in applications],
    }
    return json.dumps(payload, sort_keys=True, separators=(",", ":"))


def _validate_proxy_process(proxy_pid: int) -> int:
    if isinstance(proxy_pid, bool) or not isinstance(proxy_pid, int):
        raise WindowsWinDivertContractError("proxy pid must be an integer")
    if proxy_pid <= 0 or proxy_pid > 0xFFFFFFFF:
        raise WindowsWinDivertContractError("proxy pid is out of range")
    return proxy_pid


def build_apply_request(
    plans: Iterable[WinDivertApplicationPlan],
    *,
    session_id: str,
    plan_digest: str,
    proxy_pid: int,
    direct_listener_port: int,
) -> Mapping[str, object]:
    plan = json.loads(canonical_plan_json(plans))
    direct_port = _validate_port(
        direct_listener_port,
        "direct listener port",
    )
    proxy_port = int(plan["applications"][0]["local_proxy_port"])
    if direct_port == proxy_port:
        raise WindowsWinDivertContractError(
            "direct listener port must differ from local proxy port"
        )
    return {
        "protocol_version": PROTOCOL_VERSION,
        "command": "apply_plan",
        "session_id": _validate_session_id(session_id),
        "plan_digest": _validate_digest(plan_digest),
        "proxy": {
            "pid": _validate_proxy_process(proxy_pid),
            "direct_listener_port": direct_port,
        },
        "owned_resources": [item.resource_id for item in OWNED_RESOURCES],
        "applications": plan["applications"],
    }


def build_restore_request(*, session_id: str, plan_digest: str):
    return {
        "protocol_version": PROTOCOL_VERSION,
        "command": "restore",
        "session_id": _validate_session_id(session_id),
        "plan_digest": _validate_digest(plan_digest),
        "owned_resources": [item.resource_id for item in OWNED_RESOURCES],
    }


def validate_service_response(
    response: Mapping[str, object],
    *,
    command: str,
    session_id: str,
    plan_digest: str,
) -> Mapping[str, object]:
    if not isinstance(response, Mapping):
        raise WindowsWinDivertContractError(
            "WinDivert routing service response is not an object"
        )
    if response.get("protocol_version") != PROTOCOL_VERSION:
        raise WindowsWinDivertContractError(
            "WinDivert routing service protocol mismatch"
        )
    if response.get("command") != command:
        raise WindowsWinDivertContractError(
            "WinDivert routing service command mismatch"
        )
    if response.get("session_id") != _validate_session_id(session_id):
        raise WindowsWinDivertContractError(
            "WinDivert routing service session mismatch"
        )
    if response.get("plan_digest") != _validate_digest(plan_digest):
        raise WindowsWinDivertContractError(
            "WinDivert routing service plan digest mismatch"
        )
    if response.get("status") != "ok":
        raise WindowsWinDivertContractError(
            "WinDivert routing service rejected request: %s"
            % response.get("error", "unknown error")
        )
    return response
