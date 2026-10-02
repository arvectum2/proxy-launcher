# -*- coding: utf-8 -*-
"""Lifecycle coordinator for the WinDivert Windows routing backend."""
from __future__ import annotations

import json
import sys
from typing import Mapping

from routing_ownership import RoutingOwnershipError, RoutingOwnershipStore
from windows_windivert_service_contract import (
    OWNED_RESOURCES,
    PIPE_NAME,
    WindowsWinDivertContractError,
    build_apply_request,
    build_restore_request,
    canonical_plan_json,
    validate_service_response,
)


class NamedPipeWindowsWinDivertClient:
    """Length-delimited JSON over the local WinDivert service named pipe."""

    def __init__(self, pipe_name: str = PIPE_NAME):
        self.pipe_name = str(pipe_name)

    def request(self, payload: Mapping[str, object]) -> Mapping[str, object]:
        if not sys.platform.lower().startswith("win"):
            raise WindowsWinDivertContractError(
                "WinDivert routing service requires Windows"
            )
        encoded = json.dumps(
            payload,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        if len(encoded) > 1024 * 1024:
            raise WindowsWinDivertContractError(
                "WinDivert routing service request is too large"
            )
        frame = len(encoded).to_bytes(4, "little") + encoded
        try:
            with open(self.pipe_name, "r+b", buffering=0) as stream:
                stream.write(frame)
                header = stream.read(4)
                if len(header) != 4:
                    raise WindowsWinDivertContractError(
                        "WinDivert routing service returned a short frame"
                    )
                length = int.from_bytes(header, "little")
                if length <= 0 or length > 1024 * 1024:
                    raise WindowsWinDivertContractError(
                        "WinDivert routing service response length is invalid"
                    )
                body = stream.read(length)
        except WindowsWinDivertContractError:
            raise
        except OSError as exc:
            raise WindowsWinDivertContractError(
                "WinDivert routing service is unavailable"
            ) from exc
        if len(body) != length:
            raise WindowsWinDivertContractError(
                "WinDivert routing service returned a truncated frame"
            )
        try:
            response = json.loads(body.decode("utf-8"))
        except Exception as exc:
            raise WindowsWinDivertContractError(
                "WinDivert routing service returned invalid JSON"
            ) from exc
        if not isinstance(response, Mapping):
            raise WindowsWinDivertContractError(
                "WinDivert routing service response is not an object"
            )
        return response


def _resource_ids():
    return {item.resource_id for item in OWNED_RESOURCES}


class WindowsWinDivertController:
    def __init__(self, ownership_store: RoutingOwnershipStore, client=None):
        self.ownership_store = ownership_store
        self.client = client or NamedPipeWindowsWinDivertClient(PIPE_NAME)

    def activate(
        self,
        plans,
        *,
        proxy_pid: int,
        direct_listener_port: int,
    ):
        plan_json = canonical_plan_json(plans)
        state = self.ownership_store.prepare(
            platform="windows",
            canonical_plan_json=plan_json,
            resources=OWNED_RESOURCES,
        )
        request = build_apply_request(
            plans,
            session_id=state.session_id,
            plan_digest=state.plan_digest,
            proxy_pid=proxy_pid,
            direct_listener_port=direct_listener_port,
        )
        try:
            response = validate_service_response(
                self.client.request(request),
                command="apply_plan",
                session_id=state.session_id,
                plan_digest=state.plan_digest,
            )
            applied = set(response.get("applied_resources", ()))
            if applied != _resource_ids():
                raise WindowsWinDivertContractError(
                    "WinDivert routing service did not confirm "
                    "the exact owned resource set"
                )
            return self.ownership_store.transition("applied")
        except Exception:
            try:
                self.ownership_store.transition("restoring")
            except RoutingOwnershipError:
                pass
            raise

    def restore(self):
        state = self.ownership_store.load()
        if state.platform != "windows":
            raise RoutingOwnershipError(
                "WinDivert routing ownership state is not Windows"
            )
        if state.phase != "restoring":
            state = self.ownership_store.transition("restoring")
        response = validate_service_response(
            self.client.request(
                build_restore_request(
                    session_id=state.session_id,
                    plan_digest=state.plan_digest,
                )
            ),
            command="restore",
            session_id=state.session_id,
            plan_digest=state.plan_digest,
        )
        removed = set(response.get("removed_resources", ()))
        remaining = set(response.get("remaining_owned_resources", ()))
        if removed != _resource_ids() or remaining:
            raise WindowsWinDivertContractError(
                "WinDivert routing service did not verify complete restoration"
            )
        self.ownership_store.clear_after_verified_restore(verified=True)
        return True
