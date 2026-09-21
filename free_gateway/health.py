"""Background health/latency checks for configured upstream proxies."""

from __future__ import annotations

import asyncio
import contextlib
import ssl
import time

from .relay import upstream_connect_request


class GatewayHealthMonitor:
    def __init__(self, config, *, interval_seconds: int = 20, timeout_seconds: int = 8):
        self.config = config
        self.interval_seconds = interval_seconds
        self.timeout_seconds = timeout_seconds
        self._snapshot: dict[str, dict[str, int | bool | None]] = {}

    def snapshot(self, location_id: str) -> dict[str, int | bool | None]:
        return dict(self._snapshot.get(location_id, {"available": False, "latency_ms": None}))

    async def refresh(self) -> None:
        results = await asyncio.gather(
            *(self._probe(upstream) for upstream in self.config.upstreams.values()),
        )
        self._snapshot = {
            location_id: result
            for location_id, result in results
        }

    async def run_forever(self) -> None:
        while True:
            with contextlib.suppress(Exception):
                await self.refresh()
            await asyncio.sleep(self.interval_seconds)

    async def _probe(self, upstream):
        started = time.monotonic()
        writer = None
        try:
            context = ssl.create_default_context() if upstream.tls else None
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(
                    upstream.host,
                    upstream.port,
                    ssl=context,
                    server_hostname=upstream.host if context else None,
                ),
                timeout=self.timeout_seconds,
            )
            writer.write(upstream_connect_request(upstream, "example.com:443"))
            await writer.drain()
            header = await asyncio.wait_for(
                reader.readuntil(b"\r\n\r\n"),
                timeout=self.timeout_seconds,
            )
            status_line = header.split(b"\r\n", 1)[0]
            if b" 200 " not in status_line:
                return upstream.location_id, {"available": False, "latency_ms": None}
            latency_ms = max(0, int((time.monotonic() - started) * 1000))
            return upstream.location_id, {"available": True, "latency_ms": latency_ms}
        except (OSError, asyncio.TimeoutError, asyncio.IncompleteReadError):
            return upstream.location_id, {"available": False, "latency_ms": None}
        finally:
            if writer is not None:
                writer.close()
                with contextlib.suppress(Exception):
                    await writer.wait_closed()
