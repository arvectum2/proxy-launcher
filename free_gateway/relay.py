"""Authenticated HTTP/CONNECT listener that keeps supplier credentials server-side."""

import asyncio
import base64
import contextlib
import ssl

from .api import GatewayApi
from .http import read_request
from .tokens import SessionTokenManager


def parse_basic_auth(value: str | None):
    if not value or not value.lower().startswith("basic "):
        return None
    try:
        decoded = base64.b64decode(value[6:].strip(), validate=True).decode("utf-8")
        return tuple(decoded.split(":", 1)) if ":" in decoded else None
    except (ValueError, UnicodeDecodeError):
        return None


def upstream_connect_request(upstream, target: str) -> bytes:
    lines = [f"CONNECT {target} HTTP/1.1", f"Host: {target}", "Proxy-Connection: Keep-Alive"]
    if upstream.username or upstream.password:
        raw = f"{upstream.username}:{upstream.password}".encode("utf-8")
        credential = base64.b64encode(raw).decode("ascii")
        lines.append(f"Proxy-Authorization: Basic {credential}")
    return ("\r\n".join(lines) + "\r\n\r\n").encode("iso-8859-1")


async def _pipe(reader, writer):
    try:
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                break
            writer.write(chunk)
            await writer.drain()
    finally:
        with contextlib.suppress(Exception):
            writer.close()


class ConnectRelay:
    """One plain-HTTP origin for both public API requests and authenticated CONNECT."""

    def __init__(self, config):
        self.config = config
        self.tokens = SessionTokenManager(config.token_secret, config.session_ttl_seconds)
        self.api = GatewayApi(config)

    async def handle(self, reader, writer):
        upstream_writer = None
        try:
            method, target, _, headers, body = await read_request(reader)

            # Tailscale terminates public TLS before forwarding here. Serving the
            # API and CONNECT on this same listener lets both use public TCP/443.
            if method != "CONNECT":
                writer.write(self.api.response_for(method, target, body))
                await writer.drain()
                return

            auth = parse_basic_auth(headers.get("proxy-authorization"))
            if not auth:
                await self._reject(writer, 407, "Proxy Authentication Required")
                return

            location_id, token = auth
            upstream = self.config.upstreams.get(location_id)
            if upstream is None or not self.tokens.verify(location_id, token):
                await self._reject(writer, 407, "Proxy Authentication Required")
                return

            context = ssl.create_default_context() if upstream.tls else None
            upstream_reader, upstream_writer = await asyncio.open_connection(
                upstream.host,
                upstream.port,
                ssl=context,
                server_hostname=upstream.host if context else None,
            )
            upstream_writer.write(upstream_connect_request(upstream, target))
            await upstream_writer.drain()

            upstream_head = await upstream_reader.readuntil(b"\r\n\r\n")
            status_line = upstream_head.split(b"\r\n", 1)[0]
            if b" 200 " not in status_line:
                writer.write(b"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n")
                await writer.drain()
                return

            writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            await writer.drain()
            await asyncio.gather(
                _pipe(reader, upstream_writer),
                _pipe(upstream_reader, writer),
            )
        except (ValueError, UnicodeDecodeError, asyncio.IncompleteReadError, OSError):
            with contextlib.suppress(Exception):
                writer.write(b"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n")
                await writer.drain()
        finally:
            for stream in (upstream_writer, writer):
                if stream is not None:
                    with contextlib.suppress(Exception):
                        stream.close()
                        await stream.wait_closed()

    @staticmethod
    async def _reject(writer, status, reason):
        raw = (
            f"HTTP/1.1 {status} {reason}\r\n"
            'Proxy-Authenticate: Basic realm="Arvectum Free Gateway"\r\n'
            "Connection: close\r\n\r\n"
        ).encode("ascii")
        writer.write(raw)
        await writer.drain()
