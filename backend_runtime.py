# -*- coding: utf-8 -*-
"""Automatic operating-system backend selection for Arvectum Proxy Launcher.

Platform detection and backend construction live in this small composition
layer. Concrete backends remain independently testable and are imported only
for the selected platform.

The selected backend is bound to one explicit capability model so UI and other
callers do not infer feature support independently from ``sys.platform``.
Product support and host readiness are deliberately separate: a platform may
be supported while the current host is not safe to mutate.

Linux readiness is determined by the NetworkManager preflight. An interactive
``nmcli`` runner can be injected only for an explicitly user-authorized
PolicyKit operation; the default remains fully non-interactive.

macOS follows the same model through the ``networksetup`` preflight: a Darwin
build is a supported product platform, while the current host must expose a
readable control surface before new proxy mutation is allowed.
"""

from dataclasses import dataclass
from enum import Enum
import sys

from capability_model import capabilities_for_backend


class UnsupportedPlatformError(RuntimeError):
    """Raised when no governed system-proxy backend exists for this platform."""


class OperationalState(str, Enum):
    READY = "ready"
    AUTH_REQUIRED = "auth_required"
    UNAVAILABLE = "unavailable"


@dataclass(frozen=True)
class BackendOperationalStatus:
    backend_id: str
    platform_label: str
    state: OperationalState
    can_enable: bool
    title: str
    message: str
    reasons: tuple = ()


class BackendOperationalError(RuntimeError):
    """Raised when a new proxy mutation is unsafe on the current host."""

    def __init__(self, status):
        self.status = status
        super().__init__(status.message or status.title)


def backend_id_for_platform(platform=None):
    """Return the stable backend id for a Python ``sys.platform`` value."""
    value = str(sys.platform if platform is None else platform).strip().lower()
    if value.startswith("win"):
        return "windows"
    if value == "darwin":
        return "macos"
    if value.startswith("linux"):
        return "linux"
    raise UnsupportedPlatformError(
        "unsupported operating system for system proxy backend: %s" % (value or "<empty>")
    )


def capabilities_for_platform(platform=None):
    """Return the declared product capabilities for the selected platform."""
    return capabilities_for_backend(backend_id_for_platform(platform))


def _always_ready_status(backend_id):
    platform = capabilities_for_backend(backend_id)
    return BackendOperationalStatus(
        backend_id=backend_id,
        platform_label=platform.platform_label,
        state=OperationalState.READY,
        can_enable=True,
        title="Системный прокси доступен",
        message="Платформа готова к применению системных настроек Arvectum.",
        reasons=(),
    )


def _macos_operational_status(macos_preflight=None):
    if macos_preflight is None:
        from macos_networksetup_preflight import detect_macos_network_preflight
        macos_preflight = detect_macos_network_preflight()

    from macos_networksetup_preflight import MacOSPreflightStatus
    from macos_capability_ux import macos_capability_view

    view = macos_capability_view(macos_preflight)
    reasons = tuple(getattr(macos_preflight, "reasons", ()) or ())
    platform_label = capabilities_for_backend("macos").platform_label
    preflight_state = getattr(macos_preflight, "status", None)

    if preflight_state == MacOSPreflightStatus.READY:
        state = OperationalState.READY
    elif preflight_state == MacOSPreflightStatus.AUTH_REQUIRED:
        state = OperationalState.AUTH_REQUIRED
    else:
        state = OperationalState.UNAVAILABLE

    return BackendOperationalStatus(
        backend_id="macos",
        platform_label=platform_label,
        state=state,
        can_enable=bool(view["can_on"]),
        title=str(view["label"]),
        message=str(view["hint"]),
        reasons=reasons,
    )


def operational_status_for_platform(platform=None, linux_preflight=None, macos_preflight=None):
    """Return host-specific readiness without mutating network state.

    Windows keeps its customer-proven backend validation path. Linux/Astra
    delegates to the NetworkManager preflight and macOS delegates to the
    ``networksetup`` preflight. Injectable preflight results keep the
    composition layer deterministic in tests.
    """
    backend_id = backend_id_for_platform(platform)
    if backend_id == "windows":
        return _always_ready_status(backend_id)
    if backend_id == "macos":
        return _macos_operational_status(macos_preflight)

    if linux_preflight is None:
        from linux_networkmanager_preflight import detect_networkmanager_preflight
        linux_preflight = detect_networkmanager_preflight()

    from linux_networkmanager_preflight import PreflightStatus

    reasons = tuple(getattr(linux_preflight, "reasons", ()) or ())
    preflight_state = getattr(linux_preflight, "status", None)
    platform_label = capabilities_for_backend("linux").platform_label

    if preflight_state == PreflightStatus.READY:
        return BackendOperationalStatus(
            backend_id="linux",
            platform_label=platform_label,
            state=OperationalState.READY,
            can_enable=True,
            title="NetworkManager готов",
            message="Linux/Astra готов к безопасному применению системного прокси Arvectum.",
            reasons=reasons,
        )
    if preflight_state == PreflightStatus.AUTH_REQUIRED:
        return BackendOperationalStatus(
            backend_id="linux",
            platform_label=platform_label,
            state=OperationalState.AUTH_REQUIRED,
            can_enable=False,
            title="Требуется разрешение NetworkManager",
            message=(
                "NetworkManager поддерживает необходимые настройки, но текущему пользователю "
                "нужно отдельное разрешение PolicyKit. Arvectum не будет менять сеть без него."
            ),
            reasons=reasons,
        )
    return BackendOperationalStatus(
        backend_id="linux",
        platform_label=platform_label,
        state=OperationalState.UNAVAILABLE,
        can_enable=False,
        title="Системный прокси недоступен",
        message=(
            "На этом Linux/Astra-хосте NetworkManager сейчас не готов к безопасному "
            "применению системного прокси. Сеть оставлена без изменений."
        ),
        reasons=reasons,
    )


def operational_status_view(status):
    """Stable user-facing data for platform capability UX."""
    if not isinstance(status, BackendOperationalStatus):
        raise TypeError("BackendOperationalStatus is required")
    badge = {
        OperationalState.READY: "Доступно",
        OperationalState.AUTH_REQUIRED: "Нужно разрешение",
        OperationalState.UNAVAILABLE: "Недоступно",
    }[status.state]
    return {
        "backend_id": status.backend_id,
        "platform_label": status.platform_label,
        "state": status.state.value,
        "badge": badge,
        "enabled": bool(status.can_enable),
        "title": status.title,
        "message": status.message,
        "reasons": tuple(status.reasons),
    }


def require_enable_operational(platform=None, linux_preflight=None, macos_preflight=None):
    """Fail closed before a new proxy mutation when host preflight is not ready."""
    status = operational_status_for_platform(
        platform,
        linux_preflight=linux_preflight,
        macos_preflight=macos_preflight,
    )
    if not status.can_enable:
        raise BackendOperationalError(status)
    return status


def create_backend(platform=None, runtime_core=None, logger=None, linux_runner=None):
    """Instantiate the concrete backend selected for *platform*.

    Selection itself stays side-effect free and does not run operational
    preflight. Callers gate new mutations through ``require_enable_operational``.
    This separation is intentional: recovery/disable must remain reachable even
    when a later host preflight is degraded.

    Windows receives the captured canonical implementation adapter from the
    system-proxy runtime. This prevents the Windows backend from recursively
    calling the public dispatch functions while preserving the customer-proven
    Windows 0.2.3 mutation path.

    ``linux_runner`` is intentionally optional. When absent, LinuxBackend keeps
    its normal non-interactive subprocess runner. The interactive PolicyKit path
    supplies it only inside a child process launched after explicit user consent.
    """
    backend_id = backend_id_for_platform(platform)
    capabilities_for_backend(backend_id)
    if backend_id == "windows":
        if runtime_core is None:
            raise RuntimeError(
                "Windows backend selection requires the captured runtime core adapter"
            )
        from windows_backend import WindowsBackend
        return WindowsBackend(runtime_core=runtime_core)
    if backend_id == "macos":
        from macos_backend import MacOSBackend
        return MacOSBackend(logger=logger)
    if backend_id == "linux":
        from linux_backend import LinuxBackend, NetworkManagerClient
        from linux_desktop_proxy import detect_desktop_proxy_client
        client = NetworkManagerClient(runner=linux_runner) if linux_runner is not None else None
        desktop_client = detect_desktop_proxy_client()
        return LinuxBackend(
            client=client,
            logger=logger,
            desktop_client=desktop_client,
        )
    raise AssertionError("unreachable backend id: %s" % backend_id)
