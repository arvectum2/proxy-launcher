"""Entrypoint for the Arvectum free proxy gateway."""

import argparse
import asyncio
import contextlib

from .api import GatewayApi
from .config import GatewayConfig
from .health import GatewayHealthMonitor
from .relay import ConnectRelay


async def serve(config):
    health = GatewayHealthMonitor(config)
    await health.refresh()
    health_task = asyncio.create_task(health.run_forever())
    api = GatewayApi(config, health)
    relay = ConnectRelay(config, health)
    api_server = await asyncio.start_server(api.handle, "127.0.0.1", config.api_port)
    proxy_server = await asyncio.start_server(relay.handle, "127.0.0.1", config.proxy_port)
    try:
        async with api_server, proxy_server:
            await asyncio.gather(api_server.serve_forever(), proxy_server.serve_forever())
    finally:
        health_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await health_task


def main():
    argparse.ArgumentParser(description="Arvectum free proxy gateway").parse_args()
    asyncio.run(serve(GatewayConfig.from_env()))


if __name__ == "__main__":
    main()
