# -*- coding: utf-8 -*-
"""Platform capability model and fail-closed feature gating.

the capability model makes product capabilities explicit instead of letting UI or
callers infer them from ``sys.platform`` or backend implementation details.
"""

from dataclasses import dataclass
from enum import Enum
from typing import Dict, Iterable, Tuple


class CapabilityState(str, Enum):
    SUPPORTED = "supported"
    UNSUPPORTED = "unsupported"
    PLANNED = "planned"


class Feature(str, Enum):
    SYSTEM_PROXY = "system_proxy"
    BYPASS_RULES = "bypass_rules"
    SAFE_ROLLBACK = "safe_rollback"
    AUTOSTART = "autostart"
    APPLICATION_ROUTING = "application_routing"


@dataclass(frozen=True)
class Capability:
    feature: Feature
    state: CapabilityState
    title: str
    detail: str = ""

    @property
    def supported(self):
        return self.state == CapabilityState.SUPPORTED


@dataclass(frozen=True)
class PlatformCapabilities:
    backend_id: str
    platform_label: str
    capabilities: Tuple[Capability, ...]

    def get(self, feature):
        feature = Feature(feature)
        for capability in self.capabilities:
            if capability.feature == feature:
                return capability
        raise KeyError("capability is not declared: %s" % feature.value)

    def supports(self, feature):
        return self.get(feature).supported


class UnsupportedFeatureError(RuntimeError):
    """Raised when code tries to execute a declared unavailable feature."""

    def __init__(self, backend_id, capability):
        self.backend_id = backend_id
        self.capability = capability
        super().__init__(
            "%s is %s on %s" % (
                capability.feature.value,
                capability.state.value,
                backend_id,
            )
        )


def _common_supported():
    return (
        Capability(
            Feature.SYSTEM_PROXY,
            CapabilityState.SUPPORTED,
            "Системный прокси",
            "Безопасное включение и выключение системной маршрутизации через Arvectum.",
        ),
        Capability(
            Feature.BYPASS_RULES,
            CapabilityState.SUPPORTED,
            "Исключения",
            "Домены и адреса из no_proxy обходят прокси; пользовательские записи сохраняются.",
        ),
        Capability(
            Feature.SAFE_ROLLBACK,
            CapabilityState.SUPPORTED,
            "Восстановление сети",
            "Исходное состояние сохраняется до изменения настроек и восстанавливается ownership-aware.",
        ),
    )


def _planned_app_routing():
    return Capability(
        Feature.APPLICATION_ROUTING,
        CapabilityState.PLANNED,
        "Маршрутизация по приложениям",
        "Функция запланирована после стабильного desktop-релиза и пока не изменяет сетевые настройки.",
    )


_CAPABILITY_MATRIX: Dict[str, PlatformCapabilities] = {
    "windows": PlatformCapabilities(
        backend_id="windows",
        platform_label="Windows",
        capabilities=_common_supported() + (
            Capability(
                Feature.AUTOSTART,
                CapabilityState.SUPPORTED,
                "Автозапуск",
                "Launcher может запускать прокси при входе пользователя в Windows.",
            ),
            _planned_app_routing(),
        ),
    ),
    "macos": PlatformCapabilities(
        backend_id="macos",
        platform_label="macOS",
        capabilities=_common_supported() + (
            Capability(
                Feature.AUTOSTART,
                CapabilityState.UNSUPPORTED,
                "Автозапуск",
                "Автозапуск для macOS ещё не реализован. Прокси можно запускать вручную.",
            ),
            _planned_app_routing(),
        ),
    ),
    "linux": PlatformCapabilities(
        backend_id="linux",
        platform_label="Linux",
        capabilities=_common_supported() + (
            Capability(
                Feature.AUTOSTART,
                CapabilityState.SUPPORTED,
                "Автозапуск",
                "Per-user XDG autostart может безопасно запускать прокси при входе в Linux; интерактивный PolicyKit при фоновом старте не разрешается.",
            ),
            _planned_app_routing(),
        ),
    ),
}


def capabilities_for_backend(backend_id):
    backend_id = str(backend_id or "").strip().lower()
    try:
        return _CAPABILITY_MATRIX[backend_id]
    except KeyError:
        raise ValueError("unknown governed backend: %s" % (backend_id or "<empty>"))


def declared_backend_ids():
    return tuple(sorted(_CAPABILITY_MATRIX))


def require_feature(backend_id, feature):
    platform = capabilities_for_backend(backend_id)
    capability = platform.get(feature)
    if not capability.supported:
        raise UnsupportedFeatureError(platform.backend_id, capability)
    return capability


def unsupported_feature_view(backend_id, feature):
    """Return stable user-facing UX data for a feature control.

    Unsupported/planned functionality is intentionally visible-but-disabled.
    Hiding it would make platform differences look like bugs and would make it
    impossible to explain why a control is unavailable.
    """
    platform = capabilities_for_backend(backend_id)
    capability = platform.get(feature)
    if capability.supported:
        return {
            "visible": True,
            "enabled": True,
            "title": capability.title,
            "badge": "Доступно",
            "message": capability.detail,
            "state": capability.state.value,
        }

    badge = "Запланировано" if capability.state == CapabilityState.PLANNED else "Недоступно"
    return {
        "visible": True,
        "enabled": False,
        "title": capability.title,
        "badge": badge,
        "message": capability.detail,
        "state": capability.state.value,
    }


def capability_views(backend_id, features: Iterable[Feature] = None):
    platform = capabilities_for_backend(backend_id)
    selected = tuple(features) if features is not None else tuple(c.feature for c in platform.capabilities)
    return tuple(unsupported_feature_view(platform.backend_id, feature) for feature in selected)
