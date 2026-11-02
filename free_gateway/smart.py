"""Optional authenticated Smart Gateway: exact-host DIRECT vs supplier proxy.

The consumer iOS app sends all flows to the remote HTTP CONNECT gateway, where
approved hosts use the gateway's local egress and all others use supplier egress.
"""
import asyncio
import contextlib
from dataclasses import dataclass
import hashlib
import hmac
import ipaddress
import itertools
import json
import os
import re
import socket
import sys
import time

from .http import read_request, response
from .relay import _close_stream_writer, _pipe, open_upstream_tunnel, parse_basic_auth

_HOST_LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")


def exact_host(value):
    if not isinstance(value, str) or len(value) > 253 or not value:
        raise ValueError("invalid hostname")
    value = value.rstrip('.').lower()
    try:
        ipaddress.ip_address(value)
    except ValueError:
        pass
    else:
        raise ValueError('IP literals cannot be authorized as domains')
    if "." not in value or any(not _HOST_LABEL.fullmatch(x) for x in value.split('.')):
        raise ValueError("invalid hostname")
    return value


def connect_authority(authority):
    if not isinstance(authority, str) or authority.count(':') != 1:
        raise ValueError("expected HOST:PORT")
    hostname, port_text = authority.rsplit(':', 1)
    if not hostname or not port_text.isdecimal():
        raise ValueError("bad CONNECT authority")
    port = int(port_text)
    if not 1 <= port <= 65535:
        raise ValueError("port forbidden")
    try:
        return str(ipaddress.ip_address(hostname)), port, False
    except ValueError:
        return exact_host(hostname), port, True


@dataclass(frozen=True)
class SmartAccount:
    username: str
    token_sha256: str
    upstream_id: str


class SmartGateway:
    """Separate optional service, does not change the existing free gateway."""
    _ids = itertools.count(1)

    def __init__(self, upstreams, accounts, *, test_connector=None,
                 policy_ttl_seconds=180, clock=time.monotonic):
        self.upstreams = upstreams
        self.accounts = {a.username: a for a in accounts}
        self.policy = {a.username: frozenset() for a in accounts}
        self.policy_expiry = {a.username: 0 for a in accounts}
        self.policy_ttl_seconds = policy_ttl_seconds
        self.clock = clock
        if not 60 <= policy_ttl_seconds <= 600:
            raise ValueError("invalid policy TTL")
        self.test_connector = test_connector
        if not accounts or len(self.accounts) != len(accounts):
            raise ValueError("unique accounts required")
        for a in accounts:
            if not a.username or len(a.token_sha256) != 64 or a.upstream_id not in upstreams:
                raise ValueError("invalid account")
            bytes.fromhex(a.token_sha256)

    @classmethod
    def from_env(cls, upstreams, env=None):
        env = os.environ if env is None else env
        items = json.loads(env.get('APL_SMART_GATEWAY_ACCOUNTS_JSON', '[]'))
        return cls(upstreams, [SmartAccount(str(a['username']), str(a['token_sha256']),
                                            str(a['upstream_id'])) for a in items])

    def authenticate(self, header):
        auth = parse_basic_auth(header)
        if auth is None:
            return None
        username, token = auth
        account = self.accounts.get(username)
        if not account:
            return None
        digest = hashlib.sha256(token.encode('utf-8')).hexdigest()
        return account if hmac.compare_digest(digest, account.token_sha256) else None

    async def _direct(self, hostname, port):
        # Injectable connector is available ONLY to the isolated test harness;
        # production validates a public IP and pins it to stop DNS rebinding.
        if self.test_connector is not None:
            return await self.test_connector(hostname, port)
        resolved = await asyncio.get_running_loop().getaddrinfo(
            hostname, port, type=socket.SOCK_STREAM)
        for family, _, _, _, address in resolved:
            ip = ipaddress.ip_address(address[0])
            if ip.is_global:
                return await asyncio.wait_for(asyncio.open_connection(
                    str(ip), port, family=family), timeout=8)
        raise OSError('public address required')

    async def handle(self, reader, writer):
        outgoing = None
        stage = 'request'
        conn_id = next(self._ids)
        try:
            method, target, _, headers, body = await asyncio.wait_for(
                read_request(reader, max_header=16384, max_body=16384), timeout=10)
            if method == 'PUT' and target == '/v1/smart/policy':
                account = self.authenticate(headers.get('authorization'))
                if account is None:
                    writer.write(response(401, {'error': 'unauthorized'}))
                else:
                    try:
                        payload = json.loads(body)
                        values = payload['domains']
                        if not isinstance(values, list) or len(values) > 128:
                            raise ValueError('invalid domain list')
                        normalized = [exact_host(host) for host in values]
                        # Atomic replace; no automatic or wildcard grants.
                        self.policy[account.username] = frozenset(normalized)
                        self.policy_expiry[account.username] = self.clock() + self.policy_ttl_seconds
                        writer.write(response(200, {'ok': True, 'count': len(self.policy[account.username]),
                                                    'expires_in': self.policy_ttl_seconds}))
                    except (ValueError, KeyError, TypeError, UnicodeDecodeError):
                        writer.write(response(400, {'error': 'bad_policy'}))
                await writer.drain()
                return
            if method != 'CONNECT':
                writer.write(response(405, {'error': 'connect_required'}))
                await writer.drain()
                return
            account = self.authenticate(headers.get('proxy-authorization'))
            if account is None:
                writer.write(b'HTTP/1.1 407 Proxy Authentication Required\r\nConnection: close\r\n\r\n')
                await writer.drain()
                return
            hostname, port, is_domain = connect_authority(target)
            stage = 'outgoing'
            direct = (is_domain and port in (80, 443) and
                      self.clock() < self.policy_expiry[account.username] and
                      hostname in self.policy[account.username])
            # Fail closed. If the selected egress is down, never silently
            # substitute the other path (which may violate routing/privacy).
            if direct:
                upstream_reader, outgoing = await self._direct(hostname, port)
            else:
                upstream_reader, outgoing, _ = await open_upstream_tunnel(
                    self.upstreams[account.upstream_id], f'{hostname}:{port}',
                    connection_id=conn_id, location_id='smart')
            writer.write(b'HTTP/1.1 200 Connection Established\r\n\r\n')
            await writer.drain()
            stage = 'tunnel'
            tasks = [
                asyncio.create_task(_pipe(reader, outgoing, connection_id=conn_id, direction='client_to_egress')),
                asyncio.create_task(_pipe(upstream_reader, writer, connection_id=conn_id, direction='egress_to_client')),
            ]
            try:
                await asyncio.wait_for(
                    asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED), timeout=120)
            finally:
                for task in tasks:
                    task.cancel()
                await asyncio.gather(*tasks, return_exceptions=True)
        except (OSError, ValueError, asyncio.TimeoutError, asyncio.IncompleteReadError,
                KeyError, TypeError) as exc:
            # Never log user hostnames or authentication secrets.
            print(f'smart_gateway_failure id={conn_id} phase={stage} error={type(exc).__name__}',
                  file=sys.stderr, flush=True)
            if stage != 'tunnel':
                with contextlib.suppress(Exception):
                    writer.write(b'HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n')
                    await writer.drain()
        finally:
            await _close_stream_writer(outgoing)
            await _close_stream_writer(writer)
