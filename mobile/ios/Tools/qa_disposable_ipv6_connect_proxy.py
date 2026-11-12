#!/usr/bin/env python3
"""One-shot strict IPv6-only QA HTTP CONNECT proxy. Never a production service.

LAN listeners are safe only because destination allowlisting is exact, port is
443-only, and the process has a bounded lifetime. No client IPs, hostnames,
headers or byte payloads are emitted into logs. Do not use for general browsing.
"""
import argparse
import asyncio
import re
import socket

ALLOWED_HOSTS = frozenset(("v6.ident.me", "ipv6.icanhazip.com", "api6.ipify.org"))
ALLOWED_LITERAL_IPV6 = "2606:4700:4700::1111"
MAX_HEADER = 4096
MAX_CONCURRENCY = 12
LAB_BIND = ("127.0.0.1", "192.168.1.80")
LAB_PORT = 18081
CONNECT_RE = re.compile(rb"^CONNECT (\[[0-9a-f:]+\]|[a-z0-9.-]+):443 HTTP/1\.[01]$", re.ASCII)


def target_from_header(payload: bytes) -> str | None:
    if len(payload) > MAX_HEADER or not payload.endswith(b"\r\n\r\n"):
        return None
    first = payload.split(b"\r\n", 1)[0]
    match = CONNECT_RE.fullmatch(first)
    if not match:
        return None
    host = match.group(1).decode("ascii")
    if host.startswith("[") and host.endswith("]"):
        unwrapped = host[1:-1]
        return unwrapped if unwrapped == ALLOWED_LITERAL_IPV6 else None
    return host if host in ALLOWED_HOSTS else None


async def pipe(source: asyncio.StreamReader, dest: asyncio.StreamWriter) -> None:
    while True:
        data = await asyncio.wait_for(source.read(65536), timeout=20)
        if not data:
            return
        dest.write(data)
        await dest.drain()


class LabProxy:
    def __init__(self) -> None:
        self.semaphore = asyncio.Semaphore(MAX_CONCURRENCY)
        self.active = 0
        self.accepted = 0
        self.rejected = 0
        self.connected = 0
        self.failed = 0

    async def serve(self, reader: asyncio.StreamReader,
                    writer: asyncio.StreamWriter) -> None:
        upstream_writer = None
        async with self.semaphore:
            self.active += 1
            try:
                head = await asyncio.wait_for(
                    reader.readuntil(b"\r\n\r\n"), timeout=3)
                host = target_from_header(head)
                if host is None:
                    self.rejected += 1
                    writer.write(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
                    await writer.drain()
                    return
                self.accepted += 1
                remote_reader, upstream_writer = await asyncio.wait_for(
                    asyncio.open_connection(host, 443, family=socket.AF_INET6),
                    timeout=6)
                self.connected += 1
                if host == ALLOWED_LITERAL_IPV6:
                    # Static, public QA target only; no client address, payload,
                    # proxy secrets or source IP emitted.
                    print("APL_IPV6_QA_PROXY_LITERAL_IPV6_CONNECT_ACCEPTED", flush=True)
                writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                await writer.drain()
                tasks = [asyncio.create_task(pipe(reader, upstream_writer)),
                         asyncio.create_task(pipe(remote_reader, writer))]
                done, pending = await asyncio.wait(
                    tasks, timeout=35, return_when=asyncio.FIRST_COMPLETED)
                for task in pending:
                    task.cancel()
                await asyncio.gather(*tasks, return_exceptions=True)
            except (OSError, asyncio.TimeoutError, asyncio.IncompleteReadError,
                    asyncio.LimitOverrunError, ValueError):
                self.failed += 1
            finally:
                self.active -= 1
                if upstream_writer is not None:
                    upstream_writer.close()
                writer.close()
                try:
                    await asyncio.wait_for(writer.wait_closed(), timeout=1)
                except (OSError, asyncio.TimeoutError):
                    pass

    async def run(self, host: str, lifetime: int) -> None:
        server = await asyncio.start_server(
            self.serve, host=host, port=LAB_PORT, limit=MAX_HEADER)
        print("APL_IPV6_QA_PROXY_READY restricted_connect_v6 port_18081", flush=True)
        async with server:
            await asyncio.sleep(lifetime)
        print(f"APL_IPV6_QA_PROXY_STOP accepted={self.accepted} "
              f"connected={self.connected} rejected={self.rejected} "
              f"failed={self.failed}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", choices=LAB_BIND, default="127.0.0.1")
    parser.add_argument("--lifetime", type=int, default=140)
    options = parser.parse_args()
    if not 5 <= options.lifetime <= 180:
        parser.error("lifetime must be between 5 and 180 seconds")
    asyncio.run(LabProxy().run(options.bind, options.lifetime))


if __name__ == "__main__":
    main()
