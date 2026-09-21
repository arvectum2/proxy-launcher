"""Public metadata/session API. It never serializes supplier credentials."""

import asyncio
import json

from .http import read_request, response
from .tokens import SessionTokenManager


class GatewayApi:
    def __init__(self, config):
        self.config = config
        self.tokens = SessionTokenManager(config.token_secret, config.session_ttl_seconds)

    async def handle(self, reader, writer):
        try:
            method, target, _, _, body = await read_request(reader)
            if method == "GET" and target == "/v1/free/locations":
                payload = {"locations": self.config.public_locations()}
                raw = response(200, payload)
            elif method == "POST" and target == "/v1/free/session":
                request = json.loads(body.decode("utf-8") or "{}")
                location_id = str(request.get("location_id", ""))
                if location_id not in self.config.upstreams:
                    raw = response(404, {"error": "unknown_location"})
                else:
                    token, expires = self.tokens.issue(location_id)
                    raw = response(201, {
                        "proxy": {
                            "host": self.config.public_host,
                            "port": self.config.public_proxy_port,
                            "type": self.config.public_proxy_type,
                            "username": location_id,
                            "password": token,
                        },
                        "expires_at": expires,
                    })
            else:
                raw = response(404, {"error": "not_found"})
        except (ValueError, json.JSONDecodeError, asyncio.IncompleteReadError):
            raw = response(400, {"error": "bad_request"})
        writer.write(raw)
        await writer.drain()
        writer.close()
        await writer.wait_closed()
