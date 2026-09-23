"""Canonical system-proxy runtime composition for Arvectum Proxy Launcher.

Owns platform backend selection, capability gates and fail-closed public system-proxy operations. The Windows adapter captures the canonical WinINET implementation, while recovery/autostart and orphan-PAC handling remain explicit separate owners.
"""

from __future__ import annotations

from dataclasses import dataclass
from types import ModuleType
from typing import Any, Callable

import backend_runtime
import linux_policykit_ux
from proxy_backend import ProxyBackendConfig


@dataclass(frozen=True)
class WindowsCoreAdapter:
    """Stable view of the canonical Windows implementation captured at wiring."""

    core: ModuleType
    enable: Callable[[], Any]
    disable: Callable[[], Any]
    enabled: Callable[[], Any]
    restore_pending: Callable[[], Any]
    sync_no_proxy: Callable[[], Any]

    def __getattr__(self, name: str) -> Any:
        return getattr(self.core, name)

    def enable_system_proxy(self):
        return self.enable()

    def disable_system_proxy(self):
        return self.disable()

    def system_proxy_enabled(self):
        return self.enabled()

    def network_restore_pending(self):
        return self.restore_pending()

    def sync_client_no_proxy(self):
        return self.sync_no_proxy()


_CORE = None
_RUNTIME_PLATFORM = None
_WINDOWS_CORE = None
_SELECTED_BACKEND = None


def configure(core: ModuleType, runtime_platform: Callable[[], str]) -> None:
    """Bind the canonical composition module and runtime-platform resolver."""
    global _CORE, _RUNTIME_PLATFORM, _WINDOWS_CORE, _SELECTED_BACKEND
    _CORE = core
    _RUNTIME_PLATFORM = runtime_platform
    _SELECTED_BACKEND = None
    _WINDOWS_CORE = WindowsCoreAdapter(
        core=core,
        enable=core.enable_system_proxy,
        disable=core.disable_system_proxy,
        enabled=core.system_proxy_enabled,
        restore_pending=core.network_restore_pending,
        sync_no_proxy=core.sync_client_no_proxy,
    )


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("system proxy runtime is not configured")
    return _CORE


def _effective_runtime_platform() -> str:
    """Return production platform while preserving the historic Windows test seam."""
    core = _core()
    try:
        if core.is_windows():
            return "win32"
    except Exception:
        pass
    if _RUNTIME_PLATFORM is None:
        raise RuntimeError("runtime platform provider is not configured")
    return _RUNTIME_PLATFORM()


def resolved_backend_config(settings=None) -> ProxyBackendConfig:
    core = _core()
    settings = settings if settings is not None else core.load_settings()
    normalized = []
    seen = set()
    values = list(getattr(core, "DEFAULT_NO_PROXY", ())) + list(core.load_no_proxy())
    for raw in values:
        value = str(raw or "").strip().lower()
        if not value or value in seen:
            continue
        seen.add(value)
        normalized.append(value)
    configured_upstreams = [
        item for item in (settings.get("upstream") or [])
        if str(item.get("host") or "").strip()
    ]
    primary = configured_upstreams[0] if configured_upstreams else {}
    upstream_host = str(primary.get("host") or "").strip()
    upstream_port = int(primary.get("port") or 0)
    upstream_url = (
        "http://%s:%d" % (upstream_host, upstream_port)
        if upstream_host and upstream_port > 0
        else ""
    )
    return ProxyBackendConfig(
        pac_url=str(core.pac_url(settings)),
        http_proxy_url="http://127.0.0.1:%d" % int(settings.get("local_http_port", 8080)),
        no_proxy=tuple(normalized),
        socks_proxy_url="socks5://127.0.0.1:%d"
        % int(settings.get("local_socks_port", 1080)),
        upstream_http_proxy_url=upstream_url,
        upstream_username=str(primary.get("username") or ""),
        upstream_password=str(primary.get("password") or ""),
    )


def backend_operational_status():
    return backend_runtime.operational_status_for_platform(_effective_runtime_platform())


def backend_operational_view():
    return backend_runtime.operational_status_view(backend_operational_status())


def _interactive_policykit_context() -> bool:
    return linux_policykit_ux.policykit_interaction_requested(_effective_runtime_platform())


def get_proxy_backend():
    global _SELECTED_BACKEND
    if _SELECTED_BACKEND is None:
        linux_runner = None
        if _interactive_policykit_context():
            linux_runner = linux_policykit_ux.run_nmcli_with_policykit
        _SELECTED_BACKEND = backend_runtime.create_backend(
            platform=_effective_runtime_platform(),
            runtime_core=_WINDOWS_CORE,
            logger=_core()._log,
            linux_runner=linux_runner,
        )
        _core()._log("system proxy backend selected: %s" % _SELECTED_BACKEND.backend_id)
    return _SELECTED_BACKEND


def _reset_proxy_backend_for_tests() -> None:
    global _SELECTED_BACKEND
    _SELECTED_BACKEND = None


def _backend_failure(operation: str, error: Exception) -> None:
    try:
        _core()._log("system proxy backend %s failed: %r" % (operation, error))
    except Exception:
        pass


def _require_new_mutation_operational():
    """Guard enable/reconfiguration; disable and recovery are never gated here."""
    platform = _effective_runtime_platform()
    if not _interactive_policykit_context():
        return backend_runtime.require_enable_operational(platform)

    status = backend_runtime.operational_status_for_platform(platform)
    if status.can_enable:
        return status
    if (
        str(platform).lower().startswith("linux")
        and status.state == backend_runtime.OperationalState.AUTH_REQUIRED
    ):
        return status
    raise backend_runtime.BackendOperationalError(status)


def enable_system_proxy() -> bool:
    try:
        _require_new_mutation_operational()
        return bool(get_proxy_backend().enable(resolved_backend_config()))
    except Exception as error:
        _backend_failure("enable", error)
        return False


def refresh_system_proxy():
    """Refresh an already-owned macOS proxy route after wake.

    ``None`` means the current platform intentionally has no wake-refresh
    mutation. ``False`` means macOS refresh was attempted/refused/failed.
    """
    try:
        if _effective_runtime_platform() != "darwin":
            return None
        _require_new_mutation_operational()
        backend = get_proxy_backend()
        refresh = getattr(backend, "refresh", None)
        if not callable(refresh):
            return False
        return bool(refresh(resolved_backend_config()))
    except Exception as error:
        _backend_failure("refresh", error)
        return False


def system_proxy_disable_preflight() -> bool:
    try:
        backend = get_proxy_backend()
        preflight = getattr(backend, "disable_preflight", None)
        return True if not callable(preflight) else bool(preflight())
    except Exception as error:
        _backend_failure("disable-preflight", error)
        return False


def disable_system_proxy() -> bool:
    try:
        # Rollback must remain reachable even if readiness later degrades.
        return bool(get_proxy_backend().disable())
    except Exception as error:
        _backend_failure("disable", error)
        return False


def system_proxy_enabled() -> bool:
    try:
        return bool(get_proxy_backend().is_enabled(resolved_backend_config()))
    except Exception as error:
        _backend_failure("status", error)
        return False


def network_restore_pending() -> bool:
    try:
        return bool(get_proxy_backend().restore_pending())
    except Exception as error:
        _backend_failure("restore-pending", error)
        # Unknown recovery state is unsafe: fail closed and report pending.
        return True


def sync_client_no_proxy() -> bool:
    try:
        _require_new_mutation_operational()
        return bool(get_proxy_backend().sync_no_proxy(resolved_backend_config()))
    except Exception as error:
        _backend_failure("sync-no-proxy", error)
        return False


def install_into_core(core: ModuleType) -> ModuleType:
    """Expose canonical runtime seams through the established module object."""
    core.resolved_backend_config = resolved_backend_config
    core.backend_operational_status = backend_operational_status
    core.backend_operational_view = backend_operational_view
    core.get_proxy_backend = get_proxy_backend
    core._reset_proxy_backend_for_tests = _reset_proxy_backend_for_tests
    core._interactive_policykit_context = _interactive_policykit_context
    core._require_new_mutation_operational = _require_new_mutation_operational
    core.enable_system_proxy = enable_system_proxy
    core.refresh_system_proxy = refresh_system_proxy
    core.system_proxy_disable_preflight = system_proxy_disable_preflight
    core.disable_system_proxy = disable_system_proxy
    core.system_proxy_enabled = system_proxy_enabled
    core.network_restore_pending = network_restore_pending
    core.sync_client_no_proxy = sync_client_no_proxy
    return core
