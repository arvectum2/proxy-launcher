# -*- coding: utf-8 -*-
"""Windows per-application exclusion enforcement control plane.

The Python process never owns WFP mutation. It compiles a bounded plan for the
Arvectum privileged routing service and binds that plan to the durable
APL-ROUTE-004 ownership journal before the first service mutation.
"""
from __future__ import annotations

from dataclasses import dataclass
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
import struct
import sys
from typing import Callable, Iterable, Mapping, Optional, Tuple

from routing_ownership import (
    OwnedRoutingResource,
    RoutingOwnershipError,
    RoutingOwnershipStore,
)
from routing_rules import ApplicationIdentity
from windows_app_routing import get_wfp_app_id

PIPE_PATH = r"\\.\pipe\Arvectum.ProxyLauncher.Routing.v1"
PLAN_SCHEMA = "arvectum.windows.app-routing.v1"
PROTOCOL_SCHEMA = "arvectum.windows.routing-ipc.v1"
MAX_PIPE_MESSAGE = 64 * 1024
LOOPBACK_V4 = "127.0.0.1"


class WindowsPerAppRoutingError(RuntimeError):
    pass


@dataclass(frozen=True)
class WindowsAppRedirect:
    resource_id: str
    app_id_hex: str
    proxy_kind: str
    source_proxy_port: int
    direct_port: int

    def to_dict(self):
        return {
            "resource_id": self.resource_id,
            "app_id_hex": self.app_id_hex,
            "proxy_kind": self.proxy_kind,
            "source_proxy_port": self.source_proxy_port,
            "direct_port": self.direct_port,
            "remote_address": LOOPBACK_V4,
            "transport": "tcp",
            "family": "ipv4",
        }


@dataclass(frozen=True)
class WindowsPerAppPlan:
    redirects: Tuple[WindowsAppRedirect, ...]

    def to_dict(self):
        return {
            "schema": PLAN_SCHEMA,
            "mode": "application_exclusion_direct",
            "redirects": [item.to_dict() for item in self.redirects],
        }

    def canonical_json(self) -> str:
        return json.dumps(
            self.to_dict(), ensure_ascii=False, sort_keys=True, separators=(",", ":")
        )


def _port(value, field: str) -> int:
    if isinstance(value, bool):
        raise WindowsPerAppRoutingError("%s must be an integer port" % field)
    try:
        port = int(value)
    except (TypeError, ValueError) as exc:
        raise WindowsPerAppRoutingError("%s must be an integer port" % field) from exc
    if not 1 <= port <= 65535:
        raise WindowsPerAppRoutingError("%s is outside 1..65535" % field)
    return port


def _resource_id(identity: ApplicationIdentity, proxy_kind: str) -> str:
    seed = (identity.stable_id + "|" + proxy_kind).encode("utf-8")
    digest = hashlib.sha256(seed).hexdigest()[:24]
    return "Arvectum.ProxyLauncher.AppExclusion.%s.%s" % (digest, proxy_kind.upper())


def compile_windows_application_exclusion_enforcement_plan(
    identities: Iterable[ApplicationIdentity],
    settings: Mapping[str, object],
    direct_ports: Mapping[str, object],
    *,
    app_id_resolver: Callable[[str], bytes] = get_wfp_app_id,
) -> WindowsPerAppPlan:
    """Compile app-wide DIRECT rules into local-proxy-port redirect filters.

    This first live slice intentionally supports application exclusions only.
    Domain/CIDR destination semantics are not inferred from a connection whose
    WFP destination is already the loopback HTTP/SOCKS proxy.
    """
    source_ports = {
        "http": _port(settings.get("local_http_port", 8080), "local_http_port"),
        "socks5": _port(settings.get("local_socks_port", 1080), "local_socks_port"),
    }
    target_ports = {
        "http": _port(direct_ports.get("http"), "direct http port"),
        "socks5": _port(direct_ports.get("socks5"), "direct socks5 port"),
    }
    if set(source_ports.values()) & set(target_ports.values()):
        raise WindowsPerAppRoutingError("direct listener port collides with a normal proxy port")

    unique = {}
    for identity in identities:
        if not isinstance(identity, ApplicationIdentity):
            raise TypeError("ApplicationIdentity required")
        if identity.platform != "windows" or not identity.executable_path:
            raise WindowsPerAppRoutingError(
                "Windows live application routing requires an executable-backed Windows identity"
            )
        unique.setdefault(identity.stable_id, identity)

    redirects = []
    for stable_id in sorted(unique):
        identity = unique[stable_id]
        app_id = bytes(app_id_resolver(identity.executable_path))
        if not app_id:
            raise WindowsPerAppRoutingError("WFP returned an empty application id")
        app_hex = app_id.hex()
        for kind in ("http", "socks5"):
            redirects.append(
                WindowsAppRedirect(
                    resource_id=_resource_id(identity, kind),
                    app_id_hex=app_hex,
                    proxy_kind=kind,
                    source_proxy_port=source_ports[kind],
                    direct_port=target_ports[kind],
                )
            )
    return WindowsPerAppPlan(tuple(redirects))


def owned_resources(plan: WindowsPerAppPlan) -> Tuple[OwnedRoutingResource, ...]:
    return tuple(
        OwnedRoutingResource("wfp_filter", item.resource_id)
        for item in plan.redirects
    )


def _named_pipe_request(payload: Mapping[str, object], timeout_ms: int = 2500):
    if not sys.platform.lower().startswith("win"):
        raise WindowsPerAppRoutingError("Windows routing service IPC requires Windows")
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    if not raw or len(raw) > MAX_PIPE_MESSAGE:
        raise WindowsPerAppRoutingError("routing service request exceeds protocol limit")

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    wait = kernel32.WaitNamedPipeW
    wait.argtypes = [wintypes.LPCWSTR, wintypes.DWORD]
    wait.restype = wintypes.BOOL
    if not wait(PIPE_PATH, timeout_ms):
        raise WindowsPerAppRoutingError("Arvectum routing service is unavailable")

    create = kernel32.CreateFileW
    create.argtypes = [
        wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p,
        wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE,
    ]
    create.restype = wintypes.HANDLE
    handle = create(PIPE_PATH, 0xC0000000, 0, None, 3, 0, None)
    invalid = ctypes.c_void_p(-1).value
    handle_value = ctypes.cast(handle, ctypes.c_void_p).value if handle else None
    if handle_value in (None, invalid):
        raise WindowsPerAppRoutingError("could not open Arvectum routing service pipe")

    write = kernel32.WriteFile
    write.argtypes = [
        wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD,
        ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p,
    ]
    write.restype = wintypes.BOOL
    read = kernel32.ReadFile
    read.argtypes = [
        wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD,
        ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p,
    ]
    read.restype = wintypes.BOOL
    close = kernel32.CloseHandle
    close.argtypes = [wintypes.HANDLE]
    close.restype = wintypes.BOOL

    def write_all(data: bytes) -> None:
        offset = 0
        while offset < len(data):
            remaining = data[offset:]
            buffer = ctypes.create_string_buffer(remaining)
            sent = wintypes.DWORD()
            if not write(handle, buffer, len(remaining), ctypes.byref(sent), None):
                raise WindowsPerAppRoutingError("routing service request write failed")
            if sent.value <= 0 or sent.value > len(remaining):
                raise WindowsPerAppRoutingError("routing service request write made no progress")
            offset += sent.value

    def read_exact(length: int, label: str) -> bytes:
        out = bytearray()
        while len(out) < length:
            remaining = length - len(out)
            buffer = ctypes.create_string_buffer(remaining)
            got = wintypes.DWORD()
            if not read(handle, buffer, remaining, ctypes.byref(got), None):
                raise WindowsPerAppRoutingError("routing service %s failed" % label)
            if got.value <= 0 or got.value > remaining:
                raise WindowsPerAppRoutingError("routing service %s made no progress" % label)
            out.extend(buffer.raw[:got.value])
        return bytes(out)

    try:
        write_all(struct.pack("<I", len(raw)) + raw)
        header = read_exact(4, "reply header")
        length = struct.unpack("<I", header)[0]
        if not 1 <= length <= MAX_PIPE_MESSAGE:
            raise WindowsPerAppRoutingError("routing service reply length is invalid")
        body = read_exact(length, "reply body")
        reply = json.loads(body.decode("utf-8"))
        if not isinstance(reply, dict):
            raise WindowsPerAppRoutingError("routing service returned a non-object reply")
        return reply
    finally:
        close(handle)


class WindowsRoutingServiceClient:
    def __init__(self, transport: Optional[Callable[[Mapping[str, object]], Mapping[str, object]]] = None):
        self._transport = transport or _named_pipe_request

    def _request(self, command: str, **payload):
        request = {"schema": PROTOCOL_SCHEMA, "command": command}
        request.update(payload)
        reply = self._transport(request)
        if reply.get("schema") != PROTOCOL_SCHEMA:
            raise WindowsPerAppRoutingError("routing service protocol mismatch")
        return reply

    def apply(self, session_id: str, plan: WindowsPerAppPlan):
        return self._request("apply", session_id=session_id, plan=plan.to_dict())

    def restore(self, session_id: str, resource_ids):
        return self._request("restore", session_id=session_id, resource_ids=list(resource_ids))

    def status(self):
        return self._request("status")


class WindowsPerAppRoutingController:
    def __init__(self, ownership_path: str, *, client=None, app_id_resolver=get_wfp_app_id):
        self.store = RoutingOwnershipStore(ownership_path)
        self.client = client or WindowsRoutingServiceClient()
        self.app_id_resolver = app_id_resolver

    def apply_exclusions(self, identities, settings, direct_ports) -> bool:
        plan = compile_windows_application_exclusion_enforcement_plan(
            identities, settings, direct_ports, app_id_resolver=self.app_id_resolver
        )
        if not plan.redirects:
            return self.restore()
        state = self.store.prepare(
            platform="windows",
            canonical_plan_json=plan.canonical_json(),
            resources=owned_resources(plan),
        )
        try:
            reply = self.client.apply(state.session_id, plan)
        except Exception:
            self.store.transition("restoring")
            raise
        if not reply.get("ok"):
            self.store.transition("restoring")
            raise WindowsPerAppRoutingError(str(reply.get("error") or "routing service rejected plan"))
        self.store.transition("applied")
        return True

    def restore(self) -> bool:
        if not self.store.exists():
            return True
        state = self.store.load()
        if state.phase != "restoring":
            state = self.store.transition("restoring")
        reply = self.client.restore(
            state.session_id, [resource.resource_id for resource in state.resources]
        )
        verified = bool(reply.get("ok")) and int(reply.get("remaining_resources", -1)) == 0
        if verified:
            self.store.clear_after_verified_restore(verified=True)
        return verified


def default_ownership_path(data_dir: str) -> str:
    return os.path.join(str(data_dir), "windows_app_routing_ownership.json")
