"""Authenticated HTTP/CONNECT listener that keeps supplier credentials server-side."""

import asyncio
import base64
import contextlib
import itertools
import ssl
import sys
import time

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


class UpstreamProxyRejected(ValueError):
    pass


async def open_upstream_tunnel(
    upstream,
    target: str,
    *,
    connection_id: int | None = None,
    location_id: str | None = None,
):
    """Open one supplier CONNECT, retrying only transient transport failures."""
    last_error = None
    for attempt in range(1, UPSTREAM_CONNECT_ATTEMPTS + 1):
        writer = None
        try:
            context = ssl.create_default_context() if upstream.tls else None
            reader, writer = await asyncio.open_connection(
                upstream.host,
                upstream.port,
                ssl=context,
                server_hostname=upstream.host if context else None,
            )
            writer.write(upstream_connect_request(upstream, target))
            await writer.drain()
            head = await reader.readuntil(b"\r\n\r\n")
            status_line = head.split(b"\r\n", 1)[0]
            if b" 200 " not in status_line:
                raise UpstreamProxyRejected(status_line.decode("iso-8859-1", errors="replace"))
            return reader, writer, attempt
        except UpstreamProxyRejected:
            if writer is not None:
                with contextlib.suppress(Exception):
                    writer.close()
                    await writer.wait_closed()
            raise
        except (OSError, asyncio.IncompleteReadError, asyncio.TimeoutError) as exc:
            last_error = exc
            if writer is not None:
                with contextlib.suppress(Exception):
                    writer.close()
                    await writer.wait_closed()
            if attempt >= UPSTREAM_CONNECT_ATTEMPTS:
                raise
            print(
                f"relay_upstream_retry id={connection_id if connection_id is not None else '-'} "
                f"location={location_id or '-'} attempt={attempt} "
                f"error={type(exc).__name__}",
                file=sys.stderr,
                flush=True,
            )
            await asyncio.sleep(UPSTREAM_CONNECT_RETRY_DELAY_SECONDS * attempt)

    if last_error is not None:
        raise last_error
    raise RuntimeError("upstream retry loop exited unexpectedly")


async def _pipe(reader, writer, *, connection_id: int, direction: str):
    total = 0
    started = time.monotonic()
    outcome = "eof"
    try:
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                break
            total += len(chunk)
            writer.write(chunk)
            await writer.drain()
    except Exception as exc:
        outcome = type(exc).__name__
        raise
    finally:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        print(
            f"relay_pipe id={connection_id} dir={direction} outcome={outcome} "
            f"bytes={total} elapsed_ms={elapsed_ms}",
            file=sys.stderr,
            flush=True,
        )
        with contextlib.suppress(Exception):
            writer.close()


UPSTREAM_CONNECT_ATTEMPTS = 3
UPSTREAM_CONNECT_RETRY_DELAY_SECONDS = 0.15


class ConnectRelay:
    """One plain-HTTP origin for both public API requests and authenticated CONNECT."""

    _connection_ids = itertools.count(1)

    def __init__(self, config, health_monitor=None):
        self.config = config
        self.tokens = SessionTokenManager(config.token_secret, config.session_ttl_seconds)
        self.api = GatewayApi(config, health_monitor)

    async def handle(self, reader, writer):
        upstream_writer = None
        connection_id = next(self._connection_ids)
        location_id = None
        stage = "request"
        started = time.monotonic()
        try:
            method, target, _, headers, body = await read_request(reader)

            # Tailscale terminates public TLS before forwarding here. Serving the
            # API and CONNECT on this same listener lets both use public TCP/443.
            if method != "CONNECT":
                writer.write(self.api.response_for(method, target, body))
                await writer.drain()
                return

            stage = "auth"
            auth = parse_basic_auth(headers.get("proxy-authorization"))
            if not auth:
                await self._reject(writer, 407, "Proxy Authentication Required")
                return

            location_id, token = auth
            upstream = self.config.upstreams.get(location_id)
            if upstream is None or not self.tokens.verify(location_id, token):
                await self._reject(writer, 407, "Proxy Authentication Required")
                return

            stage = "upstream_connect"
            upstream_reader, upstream_writer, upstream_attempt = await open_upstream_tunnel(
                upstream,
                target,
                connection_id=connection_id,
                location_id=location_id,
            )
            stage = "upstream_connect_response"
            if upstream_attempt > 1:
                print(
                    f"relay_upstream_recovered id={connection_id} location={location_id} "
                    f"attempt={upstream_attempt}",
                    file=sys.stderr,
                    flush=True,
                )

            writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            await writer.drain()
            stage = "tunnel"
            print(
                f"relay_open id={connection_id} location={location_id} "
                f"elapsed_ms={int((time.monotonic() - started) * 1000)}",
                file=sys.stderr,
                flush=True,
            )
            await asyncio.gather(
                _pipe(
                    reader,
                    upstream_writer,
                    connection_id=connection_id,
                    direction="client_to_upstream",
                ),
                _pipe(
                    upstream_reader,
                    writer,
                    connection_id=connection_id,
                    direction="upstream_to_client",
                ),
            )
        except (ValueError, UnicodeDecodeError, asyncio.IncompleteReadError, OSError) as exc:
            print(
                f"relay_error id={connection_id} location={location_id or '-'} "
                f"stage={stage} error={type(exc).__name__} "
                f"elapsed_ms={int((time.monotonic() - started) * 1000)}",
                file=sys.stderr,
                flush=True,
            )
            with contextlib.suppress(Exception):
                writer.write(b"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n")
                await writer.drain()
        finally:
            if stage == "tunnel":
                print(
                    f"relay_close id={connection_id} location={location_id or '-'} "
                    f"elapsed_ms={int((time.monotonic() - started) * 1000)}",
                    file=sys.stderr,
                    flush=True,
                )
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

