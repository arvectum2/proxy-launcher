"""Environment-only configuration for the free proxy gateway."""

from dataclasses import dataclass
import json
import os


@dataclass(frozen=True)
class UpstreamProxy:
    location_id: str
    label: str
    country_code: str
    host: str
    port: int
    username: str = ""
    password: str = ""
    tls: bool = False


@dataclass(frozen=True)
class GatewayConfig:
    public_host: str
    api_port: int
    proxy_port: int
    public_proxy_port: int
    public_proxy_type: str
    token_secret: str
    session_ttl_seconds: int
    upstreams: dict[str, UpstreamProxy]

    @classmethod
    def from_env(cls, environ=None):
        env = os.environ if environ is None else environ
        secret = env.get("APL_GATEWAY_TOKEN_SECRET", "")
        if len(secret) < 32:
            raise ValueError("APL_GATEWAY_TOKEN_SECRET must contain at least 32 characters")
        raw = env.get("APL_FREE_PROXIES_JSON", "")
        if not raw:
            raise ValueError("APL_FREE_PROXIES_JSON is required")
        items = json.loads(raw)
        upstreams = {}
        for item in items:
            proxy = UpstreamProxy(
                location_id=str(item["id"]),
                label=str(item["label"]),
                country_code=str(item["country_code"]).upper(),
                host=str(item["host"]),
                port=int(item["port"]),
                username=str(item.get("username", "")),
                password=str(item.get("password", "")),
                tls=bool(item.get("tls", False)),
            )
            if not proxy.location_id or not proxy.host or proxy.port not in range(1, 65536):
                raise ValueError("invalid upstream proxy entry")
            if proxy.location_id in upstreams:
                raise ValueError("duplicate free proxy id")
            upstreams[proxy.location_id] = proxy
        if not upstreams:
            raise ValueError("at least one free proxy is required")
        return cls(
            public_host=env.get("APL_GATEWAY_PUBLIC_HOST", "127.0.0.1"),
            api_port=int(env.get("APL_GATEWAY_API_PORT", "8787")),
            proxy_port=int(env.get("APL_GATEWAY_PROXY_PORT", "8788")),
            public_proxy_port=int(env.get("APL_GATEWAY_PUBLIC_PROXY_PORT", env.get("APL_GATEWAY_PROXY_PORT", "8788"))),
            public_proxy_type=env.get("APL_GATEWAY_PUBLIC_PROXY_TYPE", "HTTP").upper(),
            token_secret=secret,
            session_ttl_seconds=min(int(env.get("APL_GATEWAY_SESSION_TTL", "600")), 3600),
            upstreams=upstreams,
        )

    def public_locations(self):
        return [
            {"id": p.location_id, "label": p.label, "country_code": p.country_code}
            for p in self.upstreams.values()
        ]
