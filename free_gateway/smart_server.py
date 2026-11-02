"""Optional APL Smart Gateway process, isolated from public free proxy service.

Safe default: loopback only. Public listening requires a valid TLS certificate
and should be deployed on a dedicated IP (not a shared CDN/Funnel IP).
"""
import asyncio
import ipaddress
import os
import ssl

from .config import GatewayConfig
from .smart import SmartGateway


async def serve(config, env=None):
    env = os.environ if env is None else env
    gateway = SmartGateway.from_env(config.upstreams, env)
    port = int(env.get('APL_SMART_GATEWAY_PORT', '8790'))
    bind = env.get('APL_SMART_GATEWAY_BIND', '127.0.0.1')
    if not 1 <= port <= 65535:
        raise ValueError('invalid listener port')
    cert = env.get('APL_SMART_GATEWAY_TLS_CERT', '')
    key = env.get('APL_SMART_GATEWAY_TLS_KEY', '')
    if bool(cert) != bool(key):
        raise ValueError('both TLS certificate and key are required')
    tls = None
    if cert:
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.minimum_version = ssl.TLSVersion.TLSv1_2
        tls.load_cert_chain(cert, key)
    if not ipaddress.ip_address(bind).is_loopback and tls is None:
        raise ValueError('external Smart Gateway listener requires TLS')
    listener = await asyncio.start_server(gateway.handle, bind, port, ssl=tls)
    async with listener:
        await listener.serve_forever()


def main():
    asyncio.run(serve(GatewayConfig.from_env()))


if __name__ == '__main__':
    main()
