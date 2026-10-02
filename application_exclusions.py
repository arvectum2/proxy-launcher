# -*- coding: utf-8 -*-
"""Application-level direct-routing exclusions control plane.

This module owns persistence and deterministic rule compilation only.  It does
not install or mutate WFP/nftables/NetworkExtension state.  A platform adapter
must truthfully report live enforcement before UI can present an exclusion as
active.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import replace
import os
import sys
from types import ModuleType
from typing import Iterable, Mapping, Optional, Tuple

from routing_rules import (
    ApplicationIdentity,
    DestinationKind,
    DestinationSelector,
    RoutingAction,
    RoutingRule,
)

SCHEMA_VERSION = 1
MAX_APP_EXCLUSIONS = 128

_CORE: ModuleType | None = None


class ApplicationExclusionError(RuntimeError):
    """Persistent state or platform capability is invalid/unsafe."""


def configure(core: ModuleType) -> None:
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("application exclusions are not configured")
    return _CORE


def _platform_name(value: Optional[str] = None) -> str:
    raw = str(sys.platform if value is None else value).strip().lower()
    if raw.startswith("win"):
        return "windows"
    if raw in {"darwin", "mac", "macos"}:
        return "macos"
    if raw.startswith("linux"):
        return "linux"
    return raw


def _identity_dict(identity: ApplicationIdentity) -> Mapping[str, str]:
    return {
        "platform": identity.platform,
        "executable_path": identity.executable_path,
        "bundle_id": identity.bundle_id,
        "package_id": identity.package_id,
        "display_name": identity.display_name,
    }


def _dedupe_identities(identities: Iterable[ApplicationIdentity]) -> Tuple[ApplicationIdentity, ...]:
    unique = {}
    for identity in identities:
        if not isinstance(identity, ApplicationIdentity):
            raise TypeError("ApplicationIdentity required")
        unique.setdefault(identity.stable_id, identity)
    result = tuple(unique[key] for key in sorted(unique))
    if len(result) > MAX_APP_EXCLUSIONS:
        raise ApplicationExclusionError(
            "too many application exclusions: maximum is %d" % MAX_APP_EXCLUSIONS
        )
    return result


def load_application_exclusions() -> Tuple[ApplicationIdentity, ...]:
    """Load canonical app exclusions.

    Corrupt/unknown state fails closed instead of being silently replaced by an
    empty list, because an empty list could change effective routing after a
    future enforcement adapter is enabled.
    """
    core = _core()
    path = core.app_exclusions_path()
    if not os.path.exists(path):
        return ()
    try:
        with open(path, "r", encoding="utf-8") as stream:
            payload = json.load(stream)
    except Exception as exc:
        raise ApplicationExclusionError("application exclusion state is unreadable") from exc
    if not isinstance(payload, Mapping) or payload.get("schema_version") != SCHEMA_VERSION:
        raise ApplicationExclusionError("unsupported application exclusion state")
    raw_apps = payload.get("applications", [])
    if not isinstance(raw_apps, list):
        raise ApplicationExclusionError("application exclusions must be a list")
    try:
        identities = tuple(ApplicationIdentity(**item) for item in raw_apps)
    except Exception as exc:
        raise ApplicationExclusionError("invalid application exclusion identity") from exc
    canonical = _dedupe_identities(identities)
    if len(canonical) != len(identities):
        raise ApplicationExclusionError("application exclusion state contains duplicates")
    return canonical


def save_application_exclusions(identities: Iterable[ApplicationIdentity]) -> bool:
    """Atomically persist application exclusions in deterministic order."""
    core = _core()
    canonical = _dedupe_identities(identities)
    payload = {
        "schema_version": SCHEMA_VERSION,
        "applications": [_identity_dict(item) for item in canonical],
    }
    encoded = json.dumps(
        payload, ensure_ascii=False, sort_keys=True, indent=2
    ) + "\n"
    try:
        core._atomic_write_text(core.app_exclusions_path(), encoded)
        core._log("application exclusions saved atomically: %d apps" % len(canonical))
        return True
    except Exception as exc:
        core._log("application exclusions save error: %r" % exc)
        return False


def _rule_id(identity: ApplicationIdentity) -> str:
    digest = hashlib.sha256(identity.stable_id.encode("utf-8")).hexdigest()[:20]
    return "app-direct-" + digest


def application_exclusion_rule(
    identity: ApplicationIdentity,
    *,
    priority: int = 50,
) -> RoutingRule:
    """Map one selected app to DIRECT for all destinations."""
    if not isinstance(identity, ApplicationIdentity):
        raise TypeError("ApplicationIdentity required")
    return RoutingRule(
        rule_id=_rule_id(identity),
        action=RoutingAction.DIRECT,
        destinations=(DestinationSelector(DestinationKind.ALL),),
        application=identity,
        priority=priority,
        enabled=True,
        description="Application exclusion: bypass Arvectum proxy",
    )


def compile_application_exclusion_rules(
    identities: Iterable[ApplicationIdentity],
) -> Tuple[RoutingRule, ...]:
    return tuple(application_exclusion_rule(item) for item in _dedupe_identities(identities))


def application_exclusion_capability(platform: Optional[str] = None) -> Mapping[str, object]:
    """Return truthful capability state for the current product baseline."""
    name = _platform_name(platform)
    if name == "windows":
        from windows_windivert_backend import (
            windows_windivert_transport_scope,
        )
        from windows_windivert_stack import (
            windows_windivert_stack_readiness,
        )
        from windows_native_stack import (
            windows_app_exclusions_preview_build,
            windows_native_stack_readiness,
        )

        windivert = windows_windivert_stack_readiness()
        preview = windows_app_exclusions_preview_build()
        legacy = windows_native_stack_readiness(
            allow_test_preview=bool(preview.get("enabled")),
            expected_source_commit=preview.get("source_commit"),
        )
        legacy_preview_ready = bool(
            preview.get("enabled")
            and legacy.get("ready")
            and legacy.get("state") == "preview_ready"
        )
        active = (
            windivert
            if windivert.get("ready")
            else (legacy if legacy_preview_ready else windivert)
        )
        backend = (
            "windivert"
            if windivert.get("ready")
            else ("legacy_wfp_preview" if legacy_preview_ready else None)
        )
        return {
            "platform": name,
            "configuration_supported": True,
            "plan_compilation_supported": True,
            "live_enforcement_supported": bool(active.get("ready")),
            "state": active.get("state", "native_stack_unavailable"),
            "backend": backend,
            "production_controller_available": True,
            "reason": active.get(
                "reason",
                "production native routing stack is unavailable",
            ),
            "windivert_stack": dict(windivert),
            "transport_scope": windows_windivert_transport_scope(),
            "native_stack": dict(legacy),
            "preview_build": dict(preview),
        }
    if name == "linux":
        return {
            "platform": name,
            "configuration_supported": True,
            "plan_compilation_supported": False,
            "live_enforcement_supported": False,
            "state": "native_adapter_pending",
            "reason": "Linux cgroup/nftables enforcement is a later real-host implementation.",
        }
    if name == "macos":
        return {
            "platform": name,
            "configuration_supported": False,
            "plan_compilation_supported": False,
            "live_enforcement_supported": False,
            "state": "managed_only",
            "reason": (
                "Consumer macOS per-app routing is not promised; the documented "
                "NetworkExtension path is constrained by managed/entitled deployment."
            ),
        }
    return {
        "platform": name,
        "configuration_supported": False,
        "plan_compilation_supported": False,
        "live_enforcement_supported": False,
        "state": "unsupported",
        "reason": "Application exclusions are unsupported on this platform.",
    }


def compile_windows_application_exclusion_plan(
    identities: Iterable[ApplicationIdentity],
    *,
    app_id_resolver=None,
):
    """Compile the exact Windows WFP bypass identities for selected apps."""
    from windows_app_routing import compile_windows_filter_plan, get_wfp_app_id

    resolver = get_wfp_app_id if app_id_resolver is None else app_id_resolver
    rules = compile_application_exclusion_rules(identities)
    return compile_windows_filter_plan(rules, app_id_resolver=resolver)


def compile_windows_application_exclusion_enforcement_plan(
    identities: Iterable[ApplicationIdentity],
    *,
    local_http_port: int,
    app_id_resolver=None,
):
    """Redirect only selected-app connections to APL's HTTP proxy into direct relay."""
    port = int(local_http_port)
    if port <= 0 or port > 65535:
        raise ApplicationExclusionError("invalid local HTTP proxy port")
    plans = compile_windows_application_exclusion_plan(
        identities, app_id_resolver=app_id_resolver
    )
    if not plans:
        return ()
    from windows_app_routing import WfpConditionPlan
    output = []
    for plan in plans:
        conditions = tuple(
            item for item in plan.conditions
            if item.condition != "ARVECTUM_DESTINATION_ALL"
        ) + (
            WfpConditionPlan("FWPM_CONDITION_IP_REMOTE_ADDRESS", "127.0.0.1/32"),
            WfpConditionPlan("FWPM_CONDITION_IP_REMOTE_PORT", str(port)),
        )
        output.append(replace(
            plan,
            operation="redirect_to_local_proxy",
            destination_kind="cidr",
            destination_value="127.0.0.1/32",
            conditions=conditions,
            note="selected app HTTP-proxy flow redirected to Arvectum direct listener",
            remote_port=port,
        ))
    return tuple(output)


def install_into_core(core: ModuleType) -> ModuleType:
    core.ApplicationExclusionError = ApplicationExclusionError
    core.load_application_exclusions = load_application_exclusions
    core.save_application_exclusions = save_application_exclusions
    core.application_exclusion_rule = application_exclusion_rule
    core.compile_application_exclusion_rules = compile_application_exclusion_rules
    core.application_exclusion_capability = application_exclusion_capability
    core.compile_windows_application_exclusion_plan = compile_windows_application_exclusion_plan
    core.compile_windows_application_exclusion_enforcement_plan = (
        compile_windows_application_exclusion_enforcement_plan
    )
    return core
