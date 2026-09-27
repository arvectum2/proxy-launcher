"""Xray VLESS/REALITY rendering for the managed-node MVP.

The server renderer accepts the REALITY private key as an explicit server-only
secret. ManagedAccess and client rendering never contain that key.
"""

from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import quote, urlencode

from .models import ManagedAccess, ManagedNode, Transport


@dataclass(frozen=True)
class RealityServerSecrets:
    private_key: str
    destination: str

    def __post_init__(self):
        if not self.private_key:
            raise ValueError("REALITY private key is required")
        if ":" not in self.destination:
            raise ValueError("destination must include host:port")


def render_client_uri(access: ManagedAccess, *, label: str = "Arvectum") -> str:
    if access.transport is not Transport.VLESS_REALITY:
        raise ValueError("only VLESS/REALITY is supported by APL-NODE-001")
    query = urlencode({
        "encryption": "none",
        "flow": "xtls-rprx-vision",
        "security": "reality",
        "sni": access.server_name,
        "fp": access.fingerprint,
        "pbk": access.reality_password,
        "sid": access.reality_short_id,
        "type": "tcp",
    })
    return (
        f"vless://{access.credential_id}@{access.host}:{access.port}"
        f"?{query}#{quote(label, safe='')}"
    )


def render_server_config(
    node: ManagedNode,
    *,
    secrets: RealityServerSecrets,
    users: list[ManagedAccess],
) -> dict:
    if node.transport is not Transport.VLESS_REALITY:
        raise ValueError("only VLESS/REALITY is supported by APL-NODE-001")

    seen = set()
    clients = []
    for access in users:
        if access.node_id != node.node_id:
            raise ValueError("managed access belongs to a different node")
        if access.transport is not node.transport:
            raise ValueError("managed access transport does not match node")
        if access.credential_id in seen:
            raise ValueError("duplicate credential_id")
        seen.add(access.credential_id)
        clients.append({
            "id": access.credential_id,
            "email": access.user_id,
            "flow": "xtls-rprx-vision",
        })

    return {
        "log": {"loglevel": "warning"},
        "inbounds": [{
            "tag": f"managed-{node.node_id}",
            "listen": "0.0.0.0",
            "port": node.port,
            "protocol": "vless",
            "settings": {
                "clients": clients,
                "decryption": "none",
            },
            "streamSettings": {
                "network": "raw",
                "security": "reality",
                "realitySettings": {
                    "show": False,
                    "target": secrets.destination,
                    "xver": 0,
                    "serverNames": [node.server_name],
                    "privateKey": secrets.private_key,
                    "shortIds": [node.reality_short_id],
                },
            },
        }],
        "outbounds": [
            {"tag": "direct", "protocol": "freedom"},
            {"tag": "blocked", "protocol": "blackhole"},
        ],
    }
