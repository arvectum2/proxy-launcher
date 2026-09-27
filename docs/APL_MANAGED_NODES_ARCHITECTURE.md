# APL Managed Nodes — architecture and phased delivery

Status: CURRENT / Owner-prioritized 2026-09-27  
Task: `APL-NODE-001`

## Decision

APL will first prove an Arvectum-managed transport model instead of treating one-for-one third-party proxy resale as the default business model.

The core economic primitive is reusable node capacity:

```
APL client
   |
VLESS + REALITY
   |
Arvectum EU node
   |
exit policy
   +-- shared datacenter IPv4
   +-- small private IPv4 pool
   +-- dedicated IPv4
   +-- later: Static ISP upstream
   +-- later: Residential upstream
   +-- later: Mobile upstream
```

Multiple customers may use the same node and, for Shared, the same public exit IPv4. Each customer has a unique managed credential and lifecycle.

## Separation of concerns

### Transport

Initial transport: **VLESS + REALITY**.

Planned fallbacks:
- Trojan/TLS;
- Shadowsocks 2022 for compatibility/experimentation.

Transport is an implementation detail. A customer buys an APL product, not a protocol.

### Exit class

The first product classes are:

1. **Shared Datacenter** — many users per exit IPv4.
2. **Private Pool** — bounded small set of users per additional IPv4.
3. **Dedicated Datacenter** — one user per additional IPv4.
4. **Static ISP** — later upstream-backed fixed ISP exit.
5. **Residential** — later upstream-backed rotating/sticky residential pool.
6. **Mobile** — later upstream-backed mobile exit.

A managed client profile must not expose upstream supplier credentials.

## Control-plane contract

The backend owns:
- node identity and country;
- node health/capacity;
- transport endpoint;
- REALITY public parameters exposed to clients;
- REALITY private key only on the node/secret store;
- user UUID / lifecycle / expiry / quota;
- exit class and exit assignment;
- optional upstream supplier routing;
- measurements and utilization.

The client receives only what is necessary to connect to Arvectum.

## MVP phases

### Phase A — repository foundation

- managed-node/product/profile data contracts;
- deterministic node selection/capacity rules;
- VLESS/REALITY client-profile renderer;
- Xray server-config renderer for fixtures/local validation;
- no secrets committed;
- focused tests.

### Android engine composition

The accepted Android TUN/routing lifecycle remains owned by the existing
`VpnService` + tun2proxy path. Managed transport is additive:

```
Android TUN
   -> tun2proxy
   -> loopback SOCKS5 (127.0.0.1)
   -> pinned libXray
   -> VLESS + REALITY
   -> Arvectum managed node
```

libXray is pinned by release digest and isolated behind an Arvectum runtime
adapter because upstream explicitly does not guarantee API stability. Its
outbound sockets must be protected from the Android VPN route and its DNS
resolver must use the selected physical network DNS endpoint.

### Phase B — Android

- add managed-profile type without removing AUTO/HTTP/HTTPS/SOCKS;
- establish VLESS/REALITY transport inside the existing VpnService path;
- preserve exclusions, failover, sleep/wake and recovery contracts;
- local/CI tests before physical use.

### Phase C — iOS

- add the same managed-profile semantic model;
- establish VLESS/REALITY inside NetworkExtension/PacketTunnel;
- preserve current privacy and recovery semantics;
- unsigned/device CI and physical build acceptance.

### Phase D — real EU node

Owner/HUMAN provisions one test VPS when Phases A-C are ready.

Measure:
- latency/RTT;
- sustained and burst throughput;
- CPU/RAM;
- simultaneous sessions;
- traffic/user/day;
- reconnect/sleep-wake behavior;
- observed exit IPv4;
- node saturation point.

Do not choose commercial density from VPS marketing limits alone.

### Phase E — productization

After measured node economics:
- Shared pricing/density;
- Private Pool users-per-IP;
- Dedicated additional IPv4 pricing;
- node allocator and capacity drain;
- multi-node failover;
- ISP supplier adapter;
- residential/mobile supplier adapters;
- billing/checkout and automatic profile creation.

## Security boundaries

- REALITY private keys, upstream supplier passwords and node administration credentials never enter client builds.
- Repository fixtures use explicit fake keys/addresses only.
- Managed profile APIs return no supplier secrets.
- Existing manual proxy profiles stay available.
- Public rollout requires rate limits, abuse controls and capacity protection.

## Spend / infrastructure boundary

Engineering and local prototypes are in scope now.

The following remain explicit Owner/HUMAN actions:
- purchasing VPS/dedicated servers;
- purchasing additional IPv4;
- entering upstream commitments/deposits;
- mutating production infrastructure;
- public sale/release.

## Immediate next action

Implement Phase A contracts and deterministic tests on `agent/apl-managed-nodes-001-20260927`.
