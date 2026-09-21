import asyncio
import base64
import json
import unittest

from free_gateway.api import GatewayApi
from free_gateway.config import GatewayConfig
from free_gateway.relay import ConnectRelay, parse_basic_auth, upstream_connect_request
from free_gateway.tokens import SessionTokenManager


SECRET = "s" * 64
PROXIES = json.dumps([{
    "id": "de-free", "label": "Germany", "country_code": "de",
    "host": "secret.supplier.test", "port": 8443,
    "username": "supplier-user", "password": "supplier-password", "tls": True,
}])


def config():
    return GatewayConfig.from_env({
        "APL_GATEWAY_PUBLIC_HOST": "gateway.arvectum.test",
        "APL_GATEWAY_TOKEN_SECRET": SECRET,
        "APL_FREE_PROXIES_JSON": PROXIES,
        "APL_GATEWAY_SESSION_TTL": "600",
    })




class FakeHealth:
    def snapshot(self, location_id):
        return {"available": True, "latency_ms": 123}


class FakeWriter:
    def __init__(self):
        self.data = bytearray()
    def write(self, data):
        self.data.extend(data)
    async def drain(self):
        pass
    def close(self):
        pass
    async def wait_closed(self):
        pass


async def call_api(request: bytes):
    reader = asyncio.StreamReader()
    reader.feed_data(request)
    reader.feed_eof()
    writer = FakeWriter()
    await GatewayApi(config()).handle(reader, writer)
    return bytes(writer.data)


async def call_relay(request: bytes):
    reader = asyncio.StreamReader()
    reader.feed_data(request)
    reader.feed_eof()
    writer = FakeWriter()
    await ConnectRelay(config()).handle(reader, writer)
    return bytes(writer.data)


class FreeGatewayTests(unittest.TestCase):
    def test_config_requires_server_secret_and_redacts_public_locations(self):
        cfg = config()
        self.assertEqual(cfg.public_locations(), [
            {"id": "de-free", "label": "Germany", "country_code": "DE"}
        ])
        rendered = json.dumps(cfg.public_locations())
        self.assertNotIn("secret.supplier.test", rendered)
        self.assertNotIn("supplier-user", rendered)
        self.assertNotIn("supplier-password", rendered)

    def test_token_is_location_bound_tamper_evident_and_expires(self):
        now = [1_000]
        manager = SessionTokenManager(SECRET, 10, clock=lambda: now[0])
        token, expires = manager.issue("de-free")
        self.assertEqual(expires, 1_010)
        self.assertTrue(manager.verify("de-free", token))
        self.assertFalse(manager.verify("us-free", token))
        self.assertFalse(manager.verify("de-free", token + "x"))
        now[0] = 1_011
        self.assertFalse(manager.verify("de-free", token))

    def test_upstream_connect_adds_supplier_auth_only_on_server_side(self):
        upstream = config().upstreams["de-free"]
        request = upstream_connect_request(upstream, "example.com:443").decode("iso-8859-1")
        expected = base64.b64encode(b"supplier-user:supplier-password").decode("ascii")
        self.assertIn("CONNECT example.com:443 HTTP/1.1", request)
        self.assertIn("Proxy-Authorization: Basic " + expected, request)

    def test_basic_gateway_auth_parser(self):
        encoded = base64.b64encode(b"de-free:token").decode("ascii")
        self.assertEqual(parse_basic_auth("Basic " + encoded), ("de-free", "token"))
        self.assertIsNone(parse_basic_auth("Bearer nope"))

    def test_locations_api_can_include_health_without_secrets(self):
        api = GatewayApi(config(), FakeHealth())
        locations = api.public_locations()
        self.assertEqual(locations[0]["available"], True)
        self.assertEqual(locations[0]["latency_ms"], 123)
        rendered = json.dumps(locations)
        self.assertNotIn("supplier-password", rendered)

    def test_locations_api_never_returns_supplier_credentials(self):
        raw = asyncio.run(call_api(
            b"GET /v1/free/locations HTTP/1.1\r\nHost: test\r\n\r\n"
        ))
        self.assertIn(b"200 OK", raw)
        self.assertIn(b"Germany", raw)
        self.assertNotIn(b"secret.supplier.test", raw)
        self.assertNotIn(b"supplier-user", raw)
        self.assertNotIn(b"supplier-password", raw)


    def test_combined_relay_listener_serves_public_locations_api(self):
        raw = asyncio.run(call_relay(
            b"GET /v1/free/locations HTTP/1.1\r\nHost: test\r\n\r\n"
        ))
        self.assertIn(b"200 OK", raw)
        self.assertIn(b"Germany", raw)
        self.assertNotIn(b"supplier-password", raw)

    def test_combined_relay_listener_serves_session_api(self):
        body = b'{"location_id":"de-free"}'
        request = (
            b"POST /v1/free/session HTTP/1.1\r\nHost: test\r\nContent-Length: "
            + str(len(body)).encode("ascii") + b"\r\n\r\n" + body
        )
        raw = asyncio.run(call_relay(request))
        self.assertIn(b"201 Created", raw)
        self.assertIn(b"gateway.arvectum.test", raw)
        self.assertNotIn(b"supplier-password", raw)

    def test_session_api_returns_gateway_not_supplier(self):
        body = b'{"location_id":"de-free"}'
        request = (
            b"POST /v1/free/session HTTP/1.1\r\nHost: test\r\nContent-Length: "
            + str(len(body)).encode("ascii") + b"\r\n\r\n" + body
        )
        raw = asyncio.run(call_api(request))
        self.assertIn(b"201 Created", raw)
        self.assertIn(b"gateway.arvectum.test", raw)
        self.assertNotIn(b"secret.supplier.test", raw)
        self.assertNotIn(b"supplier-password", raw)


if __name__ == "__main__":
    unittest.main()
