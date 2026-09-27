"""Deterministic managed-node selection."""

from __future__ import annotations

from collections.abc import Iterable

from .models import ManagedNode, Transport


class NoCapacityError(LookupError):
    pass


def select_node(
    nodes: Iterable[ManagedNode],
    *,
    country_code: str,
    transport: Transport = Transport.VLESS_REALITY,
) -> ManagedNode:
    """Pick the least-utilized healthy node with capacity.

    Stable node_id ordering is the deterministic tie-breaker so tests and
    control-plane decisions do not depend on iteration order.
    """
    country = country_code.upper()
    candidates = [
        node
        for node in nodes
        if node.healthy
        and node.country_code == country
        and node.transport is transport
        and node.remaining_capacity > 0
    ]
    if not candidates:
        raise NoCapacityError(f"no capacity for {country}/{transport.value}")
    return min(candidates, key=lambda node: (node.utilization, node.active_users, node.node_id))
