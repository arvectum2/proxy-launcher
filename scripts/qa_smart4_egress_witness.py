#!/usr/bin/env python3
"""Opt-in no-forwarding TCP witnesses for Smart4 laboratory route QA.

Server receipt is independently observed; DNS, IP and a client-side ready
signal are never interpreted as proof. Not an iPhone/VPN egress attestation.
"""
from __future__ import annotations
import argparse
from collections import Counter
from dataclasses import dataclass
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import sys
import time

TOKEN = re.compile(r"[0-9a-f]{32}\Z", re.ASCII)
MAX_PROBES = 256
MAX_DURATION = 120
MAX_DELAY_MS = 30_000
MAX_AGE_MS = 120_000
PREFIX = b"APL4/1 "
FRAME_BYTES = len(PREFIX) + 32 + 1
ACK = b"APL4/1 OK\n"

class InvalidWitness(ValueError):
    """Only fixed error codes; never user-provided network data in errors."""

def token_value(x: object) -> str:
    if not isinstance(x, str) or TOKEN.fullmatch(x) is None:
        raise InvalidWitness("INVALID_TOKEN")
    return x

def timestamp(x: object) -> int:
    if isinstance(x, bool) or not isinstance(x, int) or x < 0:
        raise InvalidWitness("INVALID_TIMESTAMP")
    return x

def load_records(path: Path, keys: frozenset[str]) -> list[dict]:
    result = []
    try:
        with path.open("rb") as stream:
            while True:
                # Bounded *binary* read: never allocate an arbitrarily long JSONL line.
                line = stream.readline(301)
                if not line:
                    break
                if len(result) >= MAX_PROBES or len(line) > 300 or not line.endswith(b"\n"):
                    raise InvalidWitness("INPUT_LIMIT")
                try:
                    entry = json.loads(line)
                except (ValueError, UnicodeDecodeError) as exc:
                    raise InvalidWitness("INVALID_JSON") from exc
                if not isinstance(entry, dict) or frozenset(entry) != keys:
                    raise InvalidWitness("INVALID_SCHEMA")
                result.append(entry)
    except OSError as exc:
        raise InvalidWitness("INPUT_UNAVAILABLE") from exc
    return result

@dataclass(frozen=True)
class LabSummary:
    observed: int
    confirmed_matches: int
    confirmed_mismatches: int
    inconclusive: int
    confirmed_direct: int
    confirmed_proxy: int
    ambiguous: int

    @property
    def attested(self) -> bool:
        return (self.confirmed_direct > 0 and self.confirmed_proxy > 0
                and self.confirmed_mismatches == 0 and self.inconclusive == 0)

    def public(self) -> dict[str, int | bool | str]:
        return {**{name: getattr(self, name) for name in
                ("observed", "confirmed_matches", "confirmed_mismatches", "inconclusive",
                 "confirmed_direct", "confirmed_proxy", "ambiguous")},
                "attested": self.attested,
                "scope": "synthetic_lab_only", "physical_egress_verified": False}

def verify(intents: Path, direct_log: Path, proxy_log: Path, *, now_ms: int | None = None) -> LabSummary:
    """Correlate separately collected positive receipts; files must be trusted server logs."""
    now = timestamp(int(time.time() * 1000) if now_ms is None else now_ms)
    plans = load_records(intents, frozenset({"token", "route", "issued_at_ms"}))
    records = {"DIRECT": load_records(direct_log, frozenset({"token", "received_at_ms"})),
               "PROXY": load_records(proxy_log, frozenset({"token", "received_at_ms"}))}
    channels = {}
    for route, items in records.items():
        bucket: dict[str, list[int]] = {}
        for item in items:
            bucket.setdefault(token_value(item["token"]), []).append(timestamp(item["received_at_ms"]))
        channels[route] = bucket
    counts: Counter[str] = Counter()
    seen: set[str] = set()
    for plan in plans:
        tok = token_value(plan["token"])
        if tok in seen:
            raise InvalidWitness("DUPLICATE_INTENT")
        seen.add(tok)
        expected = plan["route"]
        if expected not in ("DIRECT", "PROXY"):
            raise InvalidWitness("INVALID_ROUTE")
        issued = timestamp(plan["issued_at_ms"])
        counts["observed"] += 1
        positive = []
        bad = False
        for route in ("DIRECT", "PROXY"):
            receipts = channels[route].get(tok, [])
            if len(receipts) > 1:
                bad = True
            if receipts:
                received = receipts[0]
                if not (issued <= received <= issued + MAX_DELAY_MS
                        and 0 <= now - received <= MAX_AGE_MS
                        and 0 <= now - issued <= MAX_AGE_MS):
                    bad = True
                else:
                    positive.append(route)
        if bad or len(positive) > 1:
            counts["ambiguous"] += 1
            counts["inconclusive"] += 1
        elif not positive:
            counts["inconclusive"] += 1
        else:
            observed_route = positive[0]
            counts["confirmed_" + observed_route.lower()] += 1
            counts["confirmed_matches" if observed_route == expected else "confirmed_mismatches"] += 1
    if any(set(channels[route]) - seen for route in channels):
        raise InvalidWitness("UNEXPECTED_RECEIPT")
    return LabSummary(*(counts[k] for k in ("observed", "confirmed_matches",
        "confirmed_mismatches", "inconclusive", "confirmed_direct", "confirmed_proxy", "ambiguous")))

_RFC1918 = tuple(ipaddress.ip_network(value) for value in
    ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))

def safe_bind(host: str, physical_lab: bool) -> None:
    try:
        ip = ipaddress.ip_address(host)
    except ValueError as exc:
        raise InvalidWitness("NUMERIC_BIND_REQUIRED") from exc
    if ip.is_loopback:
        return
    if not physical_lab or ip.version != 4 or not any(ip in net for net in _RFC1918):
        raise InvalidWitness("LAN_BIND_REQUIRES_RFC1918_AND_OPT_IN")

class LabWitnessListener:
    """Receives token-only synthetic TCP frames; never forwards traffic."""

    def __init__(self, channel: str, host: str, port: int, output: Path,
                 *, physical_lab: bool = False, duration: int = 90, max_probes: int = 32):
        if channel not in ("DIRECT", "PROXY"):
            raise InvalidWitness("INVALID_CHANNEL")
        if not 1 <= duration <= MAX_DURATION or not 1 <= max_probes <= MAX_PROBES:
            raise InvalidWitness("LISTENER_LIMIT")
        safe_bind(host, physical_lab)
        if not 0 <= port <= 65535:
            raise InvalidWitness("INVALID_PORT")
        if output.exists():
            raise InvalidWitness("OUTPUT_ALREADY_EXISTS")
        # Windows os.open(mode=0o600) cannot enforce owner-only POSIX file
        # permissions. Refuse to collect ephemeral network evidence there.
        if os.name != "posix":
            raise InvalidWitness("POSIX_PRIVATE_LOG_REQUIRED")
        self.output, self.duration, self.max_probes = output, duration, max_probes
        family = socket.AF_INET6 if ":" in host else socket.AF_INET
        self.sock = socket.socket(family, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            self.sock.bind((host, port))
            self.sock.listen(8)
            self.sock.settimeout(0.25)
        except Exception:
            self.sock.close()
            raise
        self.bound_port = self.sock.getsockname()[1]

    @staticmethod
    def _receipt(conn: socket.socket) -> str | None:
        conn.settimeout(1.5)
        data = bytearray()
        try:
            while len(data) < FRAME_BYTES:
                chunk = conn.recv(FRAME_BYTES - len(data))
                if not chunk:
                    break
                data.extend(chunk)
                if b"\n" in chunk:
                    break
            if len(data) != FRAME_BYTES or not data.startswith(PREFIX) or data[-1:] != b"\n":
                return None
            tok = token_value(bytes(data[len(PREFIX):-1]).decode("ascii"))
            conn.sendall(ACK)
            return tok
        except (OSError, UnicodeError, InvalidWitness):
            return None

    def serve(self) -> int:
        received = 0
        attempts = 0
        deadline = time.monotonic() + self.duration
        try:
            fd = os.open(self.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as output:
                while (time.monotonic() < deadline and received < self.max_probes
                       and attempts < self.max_probes * 2):
                    try:
                        conn, _peer = self.sock.accept()
                    except socket.timeout:
                        continue
                    attempts += 1
                    with conn:
                        tok = self._receipt(conn)
                    if tok is not None:
                        output.write(json.dumps({"token": tok,
                          "received_at_ms": int(time.time() * 1000)}, separators=(",", ":")) + "\n")
                        output.flush()
                        received += 1
        finally:
            self.sock.close()
        return received

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="No-forwarding Smart4 synthetic egress witness")
    modes = parser.add_subparsers(dest="mode", required=True)
    listen = modes.add_parser("listen")
    listen.add_argument("--channel", choices=("DIRECT", "PROXY"), required=True)
    listen.add_argument("--bind", default="127.0.0.1")
    listen.add_argument("--port", type=int, default=0)
    listen.add_argument("--output", type=Path, required=True)
    listen.add_argument("--duration", type=int, default=90)
    listen.add_argument("--max-probes", type=int, default=32)
    listen.add_argument("--physical-lab", action="store_true")
    check = modes.add_parser("verify")
    check.add_argument("--intents", type=Path, required=True)
    check.add_argument("--direct", type=Path, required=True)
    check.add_argument("--proxy", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.mode == "listen":
            lab = LabWitnessListener(args.channel, args.bind, args.port, args.output,
                physical_lab=args.physical_lab, duration=args.duration, max_probes=args.max_probes)
            print(json.dumps({"listening_port": lab.bound_port, "channel": args.channel}), flush=True)
            print(json.dumps({"accepted": lab.serve()}))
            return 0
        summary = verify(args.intents, args.direct, args.proxy)
        print(json.dumps(summary.public(), sort_keys=True))
        return 0 if summary.attested else 2
    except (InvalidWitness, OSError) as exc:
        print("SMART4_WITNESS_REJECTED " + (str(exc) if isinstance(exc, InvalidWitness) else "IO_FAILURE"), file=sys.stderr)
        return 2

if __name__ == "__main__":
    raise SystemExit(main())
