"""Entrypoint for the Arvectum free proxy gateway."""

import argparse
import asyncio

from .api import GatewayApi
from .config import GatewayConfig
from .relay import ConnectRelay


async def serve(config):
    api = GatewayApi(config)
    relay = ConnectRelay(config)
    api_server = await asyncio.start_server(api.handle, "127.0.0.1", config.api_port)
    proxy_server = await asyncio.start_server(relay.handle, "127.0.0.1", config.proxy_port)
    async with api_server, proxy_server:
        await asyncio.gather(api_server.serve_forever(), proxy_server.serve_forever())


def main():
    argparse.ArgumentParser(description="Arvectum free proxy gateway").parse_args()
    asyncio.run(serve(GatewayConfig.from_env()))


if __name__ == "__main__":
    main()
