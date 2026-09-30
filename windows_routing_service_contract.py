# -*- coding: utf-8 -*-
"""Bounded control-plane contract for the privileged Windows routing service."""
from __future__ import annotations

from dataclasses import asdict, dataclass
import ipaddress
import json
import re
import uuid
from typing import Iterable, Mapping, Tuple

from routing_ownership import OwnedRoutingResource, RESOURCE_PREFIX
from windows_app_routing import WfpFilterPlan

PROTOCOL_VERSION = 3
MAX_FILTERS = 512
PIPE_NAME = r"\\.\pipe\Arvectum.ProxyLauncher.Routing"
_ALLOWED_OPERATIONS = {
    "redirect_to_local_proxy",
    "permit_bypass_arvectum_redirect",
}
_HEX = re.compile(r"^[0-9a-f]+$")
_SHA256 = re.compile(r"^[0-9a-f]{64}$")

OWNED_RESOURCES: Tuple[OwnedRoutingResource, ...] = (
    OwnedRoutingResource("wfp_provider", RESOURCE_PREFIX + "WfpProvider"),
    OwnedRoutingResource("wfp_sublayer", RESOURCE_PREFIX + "WfpSublayer"),
    OwnedRoutingResource("wfp_callout", RESOURCE_PREFIX + "ConnectRedirectV4"),
    OwnedRoutingResource("wfp_callout", RESOURCE_PREFIX + "ConnectRedirectV6"),
)


class WindowsRoutingContractError(RuntimeError):
    pass


@dataclass(frozen=True)
class ServiceFilter:
    rule_id: str
    operation: str
    application_wfp_id_hex: str
    destination_kind: str
    destination_value: str
    address_families: Tuple[int, ...]
    remote_port: int

    def to_dict(self):
        payload = asdict(self)
        payload["address_families"] = list(self.address_families)
        return payload


def _validate_session_id(value: str) -> str:
    try:
        return str(uuid.UUID(str(value)))
    except Exception as exc:
        raise WindowsRoutingContractError("invalid routing session id") from exc


def _validate_digest(value: str) -> str:
    digest = str(value or "").lower()
    if not _SHA256.fullmatch(digest):
        raise WindowsRoutingContractError("invalid routing plan digest")
    return digest


def _service_filter(plan: WfpFilterPlan) -> ServiceFilter:
    if not isinstance(plan, WfpFilterPlan):
        raise TypeError("WfpFilterPlan required")
    if not plan.enforcement_ready:
        raise WindowsRoutingContractError(
            "plan is not enforcement-ready; domain selectors are not admitted"
        )
    if plan.operation not in _ALLOWED_OPERATIONS:
        raise WindowsRoutingContractError("unsupported routing operation")
    app_id = str(plan.application_wfp_id_hex or "").lower()
    if not app_id or len(app_id) % 2 or not _HEX.fullmatch(app_id):
        raise WindowsRoutingContractError("invalid WFP application id")
    kind = str(plan.destination_kind)
    value = str(plan.destination_value)
    if kind == "all":
        families = (4, 6)
        if value != "*":
            raise WindowsRoutingContractError("invalid all-destination selector")
    elif kind == "cidr":
        try:
            network = ipaddress.ip_network(value, strict=False)
        except ValueError as exc:
            raise WindowsRoutingContractError("invalid CIDR selector") from exc
        value = str(network)
        families = (network.version,)
    else:
        raise WindowsRoutingContractError(
            "only all/CIDR selectors are admitted by production service protocol v3"
        )
    remote_port = int(getattr(plan, "remote_port", 0) or 0)
    if remote_port < 0 or remote_port > 65535:
        raise WindowsRoutingContractError("remote port is out of range")
    return ServiceFilter(
        rule_id=str(plan.rule_id),
        operation=plan.operation,
        application_wfp_id_hex=app_id,
        destination_kind=kind,
        destination_value=value,
        address_families=families,
        remote_port=remote_port,
    )


def canonical_plan_json(plans: Iterable[WfpFilterPlan]) -> str:
    filters = tuple(_service_filter(plan) for plan in plans)
    if not filters:
        raise WindowsRoutingContractError("routing plan is empty")
    if len(filters) > MAX_FILTERS:
        raise WindowsRoutingContractError("routing plan exceeds service filter limit")
    payload = {
        "protocol_version": PROTOCOL_VERSION,
        "filters": [item.to_dict() for item in filters],
    }
    return json.dumps(payload, sort_keys=True, separators=(",", ":"))


def _validate_proxy_endpoint(proxy_pid: int, proxy_port: int) -> Mapping[str, int]:
    if isinstance(proxy_pid, bool) or not isinstance(proxy_pid, int):
        raise WindowsRoutingContractError("proxy pid must be an integer")
    if isinstance(proxy_port, bool) or not isinstance(proxy_port, int):
        raise WindowsRoutingContractError("proxy port must be an integer")
    if proxy_pid <= 0 or proxy_pid > 0xFFFFFFFF:
        raise WindowsRoutingContractError("proxy pid is out of range")
    if proxy_port <= 0 or proxy_port > 65535:
        raise WindowsRoutingContractError("proxy port is out of range")
    return {"pid": proxy_pid, "port": proxy_port}


def build_apply_request(
    plans: Iterable[WfpFilterPlan],
    *,
    session_id: str,
    plan_digest: str,
    proxy_pid: int,
    proxy_port: int,
) -> Mapping[str, object]:
    plan_payload = json.loads(canonical_plan_json(plans))
    return {
        "protocol_version": PROTOCOL_VERSION,
        "command": "apply_plan",
        "session_id": _validate_session_id(session_id),
        "plan_digest": _validate_digest(plan_digest),
        "proxy": _validate_proxy_endpoint(proxy_pid, proxy_port),
        "owned_resources": [r.resource_id for r in OWNED_RESOURCES],
        "filters": plan_payload["filters"],
    }


def build_restore_request(*, session_id: str, plan_digest: str):
    return {
        "protocol_version": PROTOCOL_VERSION,
        "command": "restore",
        "session_id": _validate_session_id(session_id),
        "plan_digest": _validate_digest(plan_digest),
        "owned_resources": [r.resource_id for r in OWNED_RESOURCES],
    }


def validate_service_response(
    response: Mapping[str, object],
    *,
    command: str,
    session_id: str,
    plan_digest: str,
) -> Mapping[str, object]:
    if not isinstance(response, Mapping):
        raise WindowsRoutingContractError("routing service response is not an object")
    if response.get("protocol_version") != PROTOCOL_VERSION:
        raise WindowsRoutingContractError("routing service protocol mismatch")
    if response.get("command") != command:
        raise WindowsRoutingContractError("routing service command mismatch")
    if response.get("session_id") != _validate_session_id(session_id):
        raise WindowsRoutingContractError("routing service session mismatch")
    if response.get("plan_digest") != _validate_digest(plan_digest):
        raise WindowsRoutingContractError("routing service plan digest mismatch")
    if response.get("status") != "ok":
        raise WindowsRoutingContractError(
            "routing service rejected request: %s" % response.get("error", "unknown error")
        )
    return response
