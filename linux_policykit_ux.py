# -*- coding: utf-8 -*-
"""Linux desktop PolicyKit authorization UX primitives.

the interactive PolicyKit path keeps authorization opt-in and narrow. Read-only capability probes
never request credentials. Only a mutation explicitly started by the user from
the Linux GUI may mark its child process as interactive, and only NetworkManager
mutation commands receive ``nmcli --ask``.

This module deliberately does not use sudo, pkexec, a custom password dialog,
or a persistent privilege helper. NetworkManager/polkit remains the authority.
"""

import os
import subprocess
from typing import Any, Mapping, MutableMapping, Sequence, Tuple


POLKIT_INTERACTIVE_ENV = "ARVECTUM_POLICYKIT_INTERACTIVE"


def is_linux_platform(platform: Any) -> bool:
    return str(platform or "").strip().lower().startswith("linux")


def policykit_interaction_requested(
    platform: Any,
    environ: Mapping[str, str] = None,
) -> bool:
    """Return True only for an explicitly marked Linux child process."""
    values = os.environ if environ is None else environ
    return bool(
        is_linux_platform(platform)
        and str(values.get(POLKIT_INTERACTIVE_ENV, "")).strip() == "1"
    )


def child_environment_for_policykit(
    platform: Any,
    *,
    interactive: bool,
    environ: Mapping[str, str] = None,
) -> MutableMapping[str, str]:
    """Build a child-only environment; never persist the opt-in in the GUI."""
    result = dict(os.environ if environ is None else environ)
    result.pop(POLKIT_INTERACTIVE_ENV, None)
    if interactive and is_linux_platform(platform):
        result[POLKIT_INTERACTIVE_ENV] = "1"
    return result


def _is_networkmanager_mutation(arguments: Sequence[str]) -> bool:
    tokens = [str(item).strip().lower() for item in arguments]
    if len(tokens) < 3:
        return False
    # Ignore argv[0] (nmcli path). Global options may appear before the object.
    body = tokens[1:]
    for index, token in enumerate(body):
        if token in {"connection", "con"} and index + 1 < len(body):
            return body[index + 1] in {"modify", "mod"}
        if token in {"device", "dev"} and index + 1 < len(body):
            return body[index + 1] == "reapply"
    return False


def interactive_nmcli_arguments(arguments: Sequence[str]) -> Tuple[str, ...]:
    """Add the nmcli global ``--ask`` option only to governed mutations."""
    values = tuple(str(item) for item in arguments)
    if not values or "--ask" in values or not _is_networkmanager_mutation(values):
        return values
    return (values[0], "--ask") + values[1:]


def run_nmcli_with_policykit(arguments: Sequence[str], **kwargs: Any) -> Any:
    """Runner injected into LinuxBackend for one explicit interactive attempt."""
    return subprocess.run(list(interactive_nmcli_arguments(arguments)), **kwargs)


def linux_capability_view(
    operational_view: Mapping[str, Any],
    *,
    running: bool = False,
    platform_label: str = "Linux",
):
    """Map backend readiness to stable Linux desktop GUI state.

    ``auth_required`` is actionable, but not represented as ready. The enable
    button means "start the explicit authorization flow", not "permission is
    already granted".
    """
    state = str((operational_view or {}).get("state", "unavailable"))
    message = str((operational_view or {}).get("message", "") or "").strip()
    platform_label = str(platform_label or "Linux").strip() or "Linux"

    if state == "ready":
        return {
            "key": "linux_ready",
            "label": "ГОТОВО К ПОДКЛЮЧЕНИЮ",
            "hint": message or "NetworkManager готов к применению системного прокси Arvectum.",
            "can_on": True,
            "can_off": bool(running),
            "authorization_required": False,
        }
    if state == "auth_required":
        return {
            "key": "linux_auth_required",
            "label": "НУЖНО РАЗРЕШЕНИЕ",
            "hint": (
                "NetworkManager готов, но для изменения системного сетевого профиля "
                "требуется разрешение PolicyKit. Нажмите «Включить прокси»: Arvectum "
                "покажет подтверждение, после чего авторизацию запросит сама система."
            ),
            "can_on": True,
            "can_off": bool(running),
            "authorization_required": True,
        }
    return {
        "key": "linux_unavailable",
        "label": "СИСТЕМНЫЙ ПРОКСИ НЕДОСТУПЕН",
        "hint": message or (
            "NetworkManager на этом %s-хосте сейчас не готов к безопасному "
            "применению системного прокси. Сеть оставлена без изменений."
        ) % platform_label,
        "can_on": False,
        "can_off": bool(running),
        "authorization_required": False,
    }


def authorization_confirmation_text() -> str:
    return (
        "Для включения системного прокси NetworkManager должен изменить активный "
        "сетевой профиль.\n\n"
        "После продолжения система может показать стандартное окно PolicyKit и "
        "попросить подтвердить права пользователя/администратора. Arvectum не "
        "получает и не сохраняет пароль.\n\n"
        "Продолжить и запросить системное разрешение?"
    )
