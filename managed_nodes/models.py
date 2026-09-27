"""Pure data contracts for managed-node products.

These objects intentionally separate client-visible transport parameters from
server-only credentials and from the exit product that is sold to a customer.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import uuid


class Transport(str, Enum):
    VLESS_REALITY = "vless_reality"
    TROJAN_TLS = "trojan_tls"
    SHADOWSOCKS_2022 = "shadowsocks_2022"


class ExitClass(str, Enum):
    SHARED_DATACENTER = "shared_datacenter"
    PRIVATE_DATACENTER = "private_datacenter"
    DEDICATED_DATACENTER = "dedicated_datacenter"
    STATIC_ISP = "static_isp"
    RESIDENTIAL = "residential"
    MOBILE = "mobile"


@dataclass(frozen=True)
class ProductSpec:
    product_id: str
    exit_class: ExitClass
    country_code: str
    max_users_per_exit: int | None = None

    def __post_init__(self):
        if not self.product_id:
            raise ValueError("product_id is required")
        country = self.country_code.upper()
        if len(country) != 2 or not country.isalpha():
            raise ValueError("country_code must be a two-letter code")
        object.__setattr__(self, "country_code", country)
        if self.max_users_per_exit is not None and self.max_users_per_exit < 1:
            raise ValueError("max_users_per_exit must be positive")


@dataclass(frozen=True)
class ManagedNode:
    node_id: str
    country_code: str
    host: str
    port: int
    transport: Transport
    capacity_users: int
    active_users: int
    server_name: str
    reality_password: str
    reality_short_id: str
    fingerprint: str = "chrome"
    healthy: bool = True

    def __post_init__(self):
        if not self.node_id:
            raise ValueError("node_id is required")
        country = self.country_code.upper()
        if len(country) != 2 or not country.isalpha():
            raise ValueError("country_code must be a two-letter code")
        object.__setattr__(self, "country_code", country)
        if not self.host:
            raise ValueError("host is required")
        if self.port not in range(1, 65536):
            raise ValueError("port must be between 1 and 65535")
        if self.capacity_users < 1:
            raise ValueError("capacity_users must be positive")
        if self.active_users < 0 or self.active_users > self.capacity_users:
            raise ValueError("active_users must be within node capacity")
        if self.transport is Transport.VLESS_REALITY:
            if not self.server_name or not self.reality_password or not self.reality_short_id:
                raise ValueError("VLESS/REALITY node requires public REALITY parameters")

    @property
    def remaining_capacity(self) -> int:
        return self.capacity_users - self.active_users

    @property
    def utilization(self) -> float:
        return self.active_users / self.capacity_users


@dataclass(frozen=True)
class ManagedAccess:
    user_id: str
    node_id: str
    credential_id: str
    transport: Transport
    exit_class: ExitClass
    host: str
    port: int
    server_name: str
    reality_password: str
    reality_short_id: str
    fingerprint: str = "chrome"
    exit_id: str | None = None
    expires_at: int | None = None
    traffic_limit_bytes: int | None = None

    def __post_init__(self):
        if not self.user_id or not self.node_id:
            raise ValueError("user_id and node_id are required")
        try:
            uuid.UUID(self.credential_id)
        except (ValueError, AttributeError, TypeError) as exc:
            raise ValueError("credential_id must be a UUID") from exc
        if self.port not in range(1, 65536):
            raise ValueError("port must be between 1 and 65535")
        if self.expires_at is not None and self.expires_at < 0:
            raise ValueError("expires_at cannot be negative")
        if self.traffic_limit_bytes is not None and self.traffic_limit_bytes < 0:
            raise ValueError("traffic_limit_bytes cannot be negative")

    def client_payload(self) -> dict:
        """Return only data required by a client.

        Server-only REALITY private keys, supplier credentials and admin
        credentials are intentionally not represented by this contract.
        """
        return {
            "managed": True,
            "transport": self.transport.value,
            "exit_class": self.exit_class.value,
            "node_id": self.node_id,
            "host": self.host,
            "port": self.port,
            "credential_id": self.credential_id,
            "server_name": self.server_name,
            "reality_password": self.reality_password,
            "reality_short_id": self.reality_short_id,
            "fingerprint": self.fingerprint,
            "exit_id": self.exit_id,
            "expires_at": self.expires_at,
            "traffic_limit_bytes": self.traffic_limit_bytes,
        }
