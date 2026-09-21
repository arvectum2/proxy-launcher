"""Public metadata/session API. It never serializes supplier credentials."""

import asyncio
import json

from .http import read_request, response
from .tokens import SessionTokenManager


class GatewayApi:
    def __init__(self, config, health_monitor=None):
        self.config = config
        self.health_monitor = health_monitor
        self.tokens = SessionTokenManager(config.token_secret, config.session_ttl_seconds)

    def public_locations(self):
        locations = []
        for item in self.config.public_locations():
            rendered = dict(item)
            if self.health_monitor is not None:
                rendered.update(self.health_monitor.snapshot(item["id"]))
            locations.append(rendered)
        return locations

    def response_for(self, method: str, target: str, body: bytes) -> bytes:
        if method == "GET" and target == "/v1/free/locations":
            return response(200, {"locations": self.public_locations()})
        if method == "POST" and target == "/v1/free/session":
            request = json.loads(body.decode("utf-8") or "{}")
            location_id = str(request.get("location_id", ""))
            if location_id not in self.config.upstreams:
                return response(404, {"error": "unknown_location"})
            token, expires = self.tokens.issue(location_id)
            return response(201, {
                "proxy": {
                    "host": self.config.public_host,
                    "port": self.config.public_proxy_port,
                    "type": self.config.public_proxy_type,
                    "username": location_id,
                    "password": token,
                },
                "expires_at": expires,
            })
        return response(404, {"error": "not_found"})

    async def handle(self, reader, writer):
        try:
            method, target, _, _, body = await read_request(reader)
            raw = self.response_for(method, target, body)
        except (ValueError, json.JSONDecodeError, asyncio.IncompleteReadError):
            raw = response(400, {"error": "bad_request"})
        writer.write(raw)
        await writer.drain()
        writer.close()
        await writer.wait_closed()
