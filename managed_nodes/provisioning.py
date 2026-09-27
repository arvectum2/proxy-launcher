"""Credential issuance for managed nodes."""

from __future__ import annotations

import uuid
from collections.abc import Callable

from .models import ExitClass, ManagedAccess, ManagedNode, Transport


def issue_access(
    node: ManagedNode,
    *,
    user_id: str,
    exit_class: ExitClass,
    exit_id: str | None = None,
    expires_at: int | None = None,
    traffic_limit_bytes: int | None = None,
    credential_factory: Callable[[], uuid.UUID] = uuid.uuid4,
) -> ManagedAccess:
    if node.transport is not Transport.VLESS_REALITY:
        raise ValueError("APL-NODE-001 currently provisions VLESS/REALITY only")
    if node.remaining_capacity <= 0:
        raise ValueError("node has no remaining capacity")
    credential = credential_factory()
    return ManagedAccess(
        user_id=user_id,
        node_id=node.node_id,
        credential_id=str(credential),
        transport=node.transport,
        exit_class=exit_class,
        host=node.host,
        port=node.port,
        server_name=node.server_name,
        reality_password=node.reality_password,
        reality_short_id=node.reality_short_id,
        fingerprint=node.fingerprint,
        exit_id=exit_id,
        expires_at=expires_at,
        traffic_limit_bytes=traffic_limit_bytes,
    )
