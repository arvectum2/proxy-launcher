# -*- coding: utf-8 -*-
"""Lifecycle coordinator for the WinDivert Windows routing backend."""
from __future__ import annotations

from routing_ownership import RoutingOwnershipError, RoutingOwnershipStore
from windows_routing_controller import NamedPipeWindowsRoutingClient
from windows_windivert_service_contract import (
    OWNED_RESOURCES,
    PIPE_NAME,
    WindowsWinDivertContractError,
    build_apply_request,
    build_restore_request,
    canonical_plan_json,
    validate_service_response,
)


def _resource_ids():
    return {item.resource_id for item in OWNED_RESOURCES}


class WindowsWinDivertController:
    def __init__(self, ownership_store: RoutingOwnershipStore, client=None):
        self.ownership_store = ownership_store
        self.client = client or NamedPipeWindowsRoutingClient(PIPE_NAME)

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
