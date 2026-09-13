# APL-MOB-001 Android spike

This directory is an isolated native Android spike for the Mobile MVP. It does not alter the current Windows runtime.

## Current state

Implemented:
- native Android application skeleton;
- minimal Russian UI: proxy host, port, optional username/password, SOCKS5/HTTP selector, one `ВКЛ` button;
- Android VPN permission flow via `VpnService.prepare()`;
- platform-neutral `ProxyProfile` model;
- `ProxyEngineAdapter` boundary so the product is not coupled to sing-box;
- `ProxyVpnService` declaration and service skeleton.

Intentionally **not** implemented yet:
- packet forwarding/TUN engine;
- credential persistence;
- real connect/disconnect lifecycle;
- reconnect/failover.

The spike refuses to pretend that a tunnel works before a real engine is wired. This avoids creating a VPN interface that silently blackholes device traffic.

## Next implementation slice

1. Decide engine for the first dogfood build (sing-box adapter vs a smaller tun2socks/SOCKS implementation).
2. Add secure credential storage.
3. Wire the engine to `ProxyVpnService` and create the TUN interface only after configuration validation.
4. Add a debug acceptance check that confirms the public IP changes through the configured proxy.
