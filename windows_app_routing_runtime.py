# -*- coding: utf-8 -*-
"""Lifecycle bridge between APL runtime and the privileged Windows routing service."""
from __future__ import annotations

import os
from types import ModuleType
from typing import Optional

from windows_per_app_routing import (
    WindowsPerAppRoutingController,
    WindowsPerAppRoutingError,
    WindowsRoutingServiceClient,
    default_ownership_path,
)

_CORE: ModuleType | None = None


def configure(core: ModuleType) -> None:
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("Windows app routing runtime is not configured")
    return _CORE


def windows_app_routing_ownership_path() -> str:
    return default_ownership_path(_core().data_dir())


def _controller(*, client=None, app_id_resolver=None):
    kwargs = {}
    if client is not None:
        kwargs["client"] = client
    if app_id_resolver is not None:
        kwargs["app_id_resolver"] = app_id_resolver
    return WindowsPerAppRoutingController(windows_app_routing_ownership_path(), **kwargs)


def windows_app_routing_pending() -> bool:
    if not _core().is_windows():
        return False
    return os.path.exists(windows_app_routing_ownership_path())


def windows_app_routing_service_status(client: Optional[WindowsRoutingServiceClient] = None):
    if not _core().is_windows():
        return {"available": False, "state": "not_windows"}
    try:
        reply = (client or WindowsRoutingServiceClient()).status()
    except Exception as exc:
        return {
            "available": False,
            "state": "service_unavailable",
            "reason": str(exc),
        }
    ready = bool(reply.get("ok")) and reply.get("state") in {"ready", "applied"}
    return {
        "available": ready,
        "state": str(reply.get("state") or "unknown"),
        "driver_loaded": bool(reply.get("driver_loaded")),
        "filters": int(reply.get("filters") or 0),
    }


def reconcile_windows_app_routing_before_start(*, client=None) -> bool:
    """Restore any interrupted owned WFP session before a new proxy session."""
    core = _core()
    if not core.is_windows() or not windows_app_routing_pending():
        return True
    try:
        return bool(_controller(client=client).restore())
    except Exception as exc:
        core._log("Windows app routing recovery failed before start: %r" % exc)
        return False


def apply_windows_application_exclusions(proxy, *, client=None, app_id_resolver=None) -> bool:
    core = _core()
    if not core.is_windows():
        return True
    identities = core.load_application_exclusions()
    if not identities:
        return True
    ports = proxy.app_direct_ports()
    if set(ports) != {"http", "socks5"}:
        core._log("Windows app routing aborted: direct listener endpoints are unavailable")
        return False
    try:
        return bool(
            _controller(client=client, app_id_resolver=app_id_resolver).apply_exclusions(
                identities, core.load_settings(), ports
            )
        )
    except Exception as exc:
        core._log("Windows app routing apply failed: %r" % exc)
        return False


def restore_windows_application_routing(*, client=None) -> bool:
    core = _core()
    if not core.is_windows() or not windows_app_routing_pending():
        return True
    try:
        return bool(_controller(client=client).restore())
    except Exception as exc:
        core._log("Windows app routing restore failed: %r" % exc)
        return False


def install_into_core(core: ModuleType) -> ModuleType:
    core.WindowsPerAppRoutingError = WindowsPerAppRoutingError
    core.windows_app_routing_ownership_path = windows_app_routing_ownership_path
    core.windows_app_routing_pending = windows_app_routing_pending
    core.windows_app_routing_service_status = windows_app_routing_service_status
    core.reconcile_windows_app_routing_before_start = reconcile_windows_app_routing_before_start
    core.apply_windows_application_exclusions = apply_windows_application_exclusions
    core.restore_windows_application_routing = restore_windows_application_routing
    return core
