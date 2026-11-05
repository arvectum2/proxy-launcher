#!/usr/bin/env python3
"""Bounded physical-iPhone QA relay: fixed synthetic CONNECT to one loopback witness.

Not a general proxy. Never forwards arbitrary hosts, URLs or user traffic.
"""
from __future__ import annotations
import argparse
import socket
import sys
import time
from qa_smart4_egress_witness import (ACK, FRAME_BYTES, PREFIX, InvalidWitness,
                                        safe_bind, token_value)

CONNECT = (b"CONNECT apl-smart4-proxy.invalid:443 HTTP/1.1\r\n"
           b"Host: apl-smart4-proxy.invalid:443\r\n\r\n")
ESTABLISHED = b"HTTP/1.1 200\r\n\r\n"

def read_exact(sock: socket.socket, size: int) -> bytes:
    result = bytearray()
    while len(result) < size:
        chunk = sock.recv(size - len(result))
        if not chunk:
            return b""
        result.extend(chunk)
    return bytes(result)


def relay_one(client: socket.socket, witness_port: int) -> bool:
    client.settimeout(3)
    if read_exact(client, len(CONNECT)) != CONNECT:
        return False
    client.sendall(ESTABLISHED)
    frame = read_exact(client, FRAME_BYTES)
    if not (len(frame) == FRAME_BYTES and frame.startswith(PREFIX) and frame.endswith(b"\n")):
        return False
    try:
        token_value(frame[len(PREFIX):-1].decode("ascii"))
        # The only possible upstream is this same Mac's fixed loopback witness.
        with socket.create_connection(("127.0.0.1", witness_port), timeout=3) as upstream:
            upstream.settimeout(3)
            upstream.sendall(frame)
            if read_exact(upstream, len(ACK)) != ACK:
                return False
        client.sendall(ACK)
        return True
    except (OSError, UnicodeError, InvalidWitness):
        return False


def serve(bind: str, port: int, witness_port: int, *, duration: int = 90,
          max_probes: int = 1) -> tuple[int, int]:
    safe_bind(bind, physical_lab=True)
    if not (1 <= duration <= 120 and 1 <= max_probes <= 256
            and 1 <= witness_port <= 65535 and 0 <= port <= 65535):
        raise InvalidWitness("RELAY_LIMIT")
    accepted, forwarded = 0, 0
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((bind, port))
        listener.listen(4)
        listener.settimeout(0.25)
        bound = listener.getsockname()[1]
        print(f"RELAY_LISTENING_PORT={bound}", flush=True)
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline and accepted < max_probes * 2 and forwarded < max_probes:
            try:
                client, _peer = listener.accept()
            except socket.timeout:
                continue
            accepted += 1
            with client:
                try:
                    if relay_one(client, witness_port):
                        forwarded += 1
                except OSError:
                    pass
    return accepted, forwarded


def main() -> int:
    p = argparse.ArgumentParser(description="Synthetic-only single-witness CONNECT relay")
    p.add_argument("--bind", required=True)
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--witness-port", type=int, required=True)
    p.add_argument("--duration", type=int, default=90)
    p.add_argument("--max-probes", type=int, default=1)
    args = p.parse_args()
    try:
        attempts, success = serve(args.bind, args.port, args.witness_port,
                                  duration=args.duration, max_probes=args.max_probes)
    except (OSError, InvalidWitness) as exc:
        print("SMART4_RELAY_REJECTED " + (str(exc) if isinstance(exc, InvalidWitness)
                                          else "IO_FAILURE"), file=sys.stderr)
        return 2
    print(f"RELAY_ATTEMPTS={attempts} VERIFIED_FORWARDINGS={success}")
    return 0 if success else 2

if __name__ == "__main__":
    raise SystemExit(main())
