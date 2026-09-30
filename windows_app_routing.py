# -*- coding: utf-8 -*-
"""Read-only Windows WFP application identity and filter-plan prototype.

the Windows application-routing gate deliberately stops before live WFP filter/callout installation.
Live WFP redirection requires a separately reviewed native privileged component.
"""
from dataclasses import dataclass
import ctypes
from ctypes import wintypes
import ipaddress
import os
import sys
from typing import Callable, Optional, Tuple

from routing_rules import DestinationKind, RoutingAction, RoutingRule, ordered_rules


class WindowsAppRoutingError(RuntimeError):
    pass


class FWP_BYTE_BLOB(ctypes.Structure):
    _fields_ = [("size", ctypes.c_uint32), ("data", ctypes.POINTER(ctypes.c_ubyte))]


@dataclass(frozen=True)
class WfpConditionPlan:
    condition: str
    value: str


@dataclass(frozen=True)
class WfpFilterPlan:
    rule_id: str
    operation: str
    layer_v4: str
    layer_v6: str
    application_stable_id: str
    application_wfp_id_hex: str
    destination_kind: str
    destination_value: str
    conditions: Tuple[WfpConditionPlan, ...]
    enforcement_ready: bool
    note: str
    remote_port: int = 0


def get_wfp_app_id(executable_path: str, *, platform: Optional[str] = None) -> bytes:
    """Retrieve WFP's application id for an executable without installing filters."""
    current = str(sys.platform if platform is None else platform).lower()
    if not current.startswith("win"):
        raise WindowsAppRoutingError("WFP application id retrieval requires Windows")
    path = os.path.abspath(os.path.expanduser(str(executable_path or "")))
    if not os.path.isfile(path):
        raise WindowsAppRoutingError("application executable does not exist: %s" % path)
    try:
        library = ctypes.WinDLL("Fwpuclnt.dll")
    except Exception as exc:
        raise WindowsAppRoutingError("Fwpuclnt.dll is unavailable") from exc
    get_id = library.FwpmGetAppIdFromFileName0
    get_id.argtypes = [wintypes.LPCWSTR, ctypes.POINTER(ctypes.POINTER(FWP_BYTE_BLOB))]
    get_id.restype = wintypes.DWORD
    free_memory = library.FwpmFreeMemory0
    free_memory.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
    free_memory.restype = None
    pointer = ctypes.POINTER(FWP_BYTE_BLOB)()
    result = int(get_id(path, ctypes.byref(pointer)))
    if result != 0 or not pointer:
        raise WindowsAppRoutingError("FwpmGetAppIdFromFileName0 failed: 0x%08X" % (result & 0xFFFFFFFF))
    try:
        blob = pointer.contents
        return bytes(ctypes.string_at(blob.data, blob.size)) if blob.size else b""
    finally:
        raw = ctypes.cast(pointer, ctypes.c_void_p)
        free_memory(ctypes.byref(raw))


def _families_for_destination(kind: DestinationKind, value: str):
    if kind == DestinationKind.CIDR:
        network = ipaddress.ip_network(value, strict=False)
        return (4,) if network.version == 4 else (6,)
    return (4, 6)


def compile_windows_filter_plan(
    rules,
    *,
    app_id_resolver: Callable[[str], bytes] = get_wfp_app_id,
) -> Tuple[WfpFilterPlan, ...]:
    """Compile routing-rule ownership rules into a non-mutating WFP plan.

    Domain selectors are intentionally not enforcement-ready because WFP ALE
    destination conditions are address-based and a production DNS strategy is
    required to preserve domain semantics across CDN/DNS changes.
    """
    plans = []
    for rule in ordered_rules(rules):
        if not isinstance(rule, RoutingRule):
            raise TypeError("RoutingRule required")
        app = rule.application
        if app is None or app.platform != "windows" or not app.executable_path:
            raise WindowsAppRoutingError("Windows prototype requires an executable-backed Windows application identity")
        app_id = bytes(app_id_resolver(app.executable_path))
        if not app_id:
            raise WindowsAppRoutingError("empty WFP application id")
        operation = "redirect_to_local_proxy" if rule.action == RoutingAction.PROXY else "permit_bypass_arvectum_redirect"
        for destination in rule.destinations:
            conditions = [WfpConditionPlan("FWPM_CONDITION_ALE_APP_ID", app_id.hex())]
            ready = True
            note = "application-aware WFP plan; live enforcement not installed by this module"
            if destination.kind == DestinationKind.CIDR:
                conditions.append(WfpConditionPlan("FWPM_CONDITION_IP_REMOTE_ADDRESS", destination.value))
            elif destination.kind == DestinationKind.DOMAIN:
                conditions.append(WfpConditionPlan("ARVECTUM_DOMAIN_POLICY_INPUT", destination.value))
                ready = False
                note = "domain selector requires DNS-aware address lifecycle before WFP enforcement"
            else:
                conditions.append(WfpConditionPlan("ARVECTUM_DESTINATION_ALL", "*"))
            plans.append(WfpFilterPlan(
                rule_id=rule.rule_id,
                operation=operation,
                layer_v4="FWPM_LAYER_ALE_CONNECT_REDIRECT_V4",
                layer_v6="FWPM_LAYER_ALE_CONNECT_REDIRECT_V6",
                application_stable_id=app.stable_id,
                application_wfp_id_hex=app_id.hex(),
                destination_kind=destination.kind.value,
                destination_value=destination.value,
                conditions=tuple(conditions),
                enforcement_ready=ready,
                note=note,
                remote_port=0,
            ))
    return tuple(plans)
