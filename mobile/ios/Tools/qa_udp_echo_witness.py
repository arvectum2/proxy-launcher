#!/usr/bin/env python3
"""Bounded IPv6 UDP echo witness for explicit iPhone PacketTunnel QA.

Never a production relay. Reply only to a tiny test token without
amplification, reject non-global bind addresses, and self-terminate.
Do not log network addresses or packet payloads.
"""
import argparse
import ipaddress
import re
import socket
import time

TOKEN = re.compile(rb"APL030-[0-9a-f]{32}\Z")
MAX_PACKET = 128
DEFAULT_PORT = 18991


def valid_bind(value: str) -> str:
    try:
        address = ipaddress.IPv6Address(value)
    except ipaddress.AddressValueError as exc:
        raise argparse.ArgumentTypeError("A concrete public IPv6 bind address is required") from exc
    if not address.is_global or address.ipv4_mapped is not None:
        raise argparse.ArgumentTypeError("Only a public global-unicast IPv6 address is permitted")
    return str(address)


def accepted(data: bytes) -> bool:
    return len(data) == 39 and TOKEN.fullmatch(data) is not None


def run(bind: str, port: int, lifetime: int, max_echoes: int) -> None:
    accepted_count = 0
    rejected_count = 0
    deadline = time.monotonic() + lifetime
    with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as server:
        server.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        server.bind((bind, port))
        print("APL030_UDP_WITNESS_READY_IPV6_TOKEN_ONLY", flush=True)
        while accepted_count < max_echoes:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            server.settimeout(min(remaining, 1.0))
            try:
                packet, peer = server.recvfrom(MAX_PACKET + 1)
            except socket.timeout:
                continue
            if not accepted(packet):
                rejected_count += 1
                continue
            # Fixed-size echo, 1:1 bytes; never a proxy or arbitrary reflector.
            server.sendto(packet, peer)
            accepted_count += 1
    print(f"APL030_UDP_WITNESS_STOP echoed={accepted_count} rejected={rejected_count}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", type=valid_bind, required=True)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--lifetime", type=int, default=75)
    parser.add_argument("--max-echoes", type=int, default=8)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("port must be unprivileged (1024..65535)")
    if not 5 <= args.lifetime <= 120:
        parser.error("lifetime must be 5..120 seconds")
    if not 1 <= args.max_echoes <= 16:
        parser.error("max-echoes must be 1..16")
    run(args.bind, args.port, args.lifetime, args.max_echoes)


if __name__ == "__main__":
    main()
