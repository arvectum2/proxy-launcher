#!/usr/bin/env python3
"""One-command bounded local Smart4 witness rehearsal, without any iPhone.

All three processes use loopback; this DOES NOT attest physical PacketTunnel
routing or independent externally trusted egress. Never touches VPN/Keychain.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import secrets
import select
import socket
import subprocess
import sys
import tempfile
import time

from qa_smart4_egress_witness import (ACK, PREFIX, InvalidWitness, verify)
from qa_smart4_physical_proxy_relay import CONNECT, ESTABLISHED, read_exact

ROOT = Path(__file__).resolve().parent
MAX_BOOT_SECONDS = 6
MAX_IO_SECONDS = 4


def _read_ready(proc: subprocess.Popen[bytes], prefix: bytes) -> int:
    if proc.stdout is None:
        raise InvalidWitness("SERVER_START_FAILED")
    streams, _, _ = select.select([proc.stdout], [], [], MAX_BOOT_SECONDS)
    if not streams:
        raise InvalidWitness("SERVER_START_TIMEOUT")
    line = proc.stdout.readline(150)
    if not line or len(line) > 140:
        raise InvalidWitness("SERVER_START_FAILED")
    try:
        if prefix == b"RELAY_LISTENING_PORT=":
            port = int(line.removeprefix(prefix).strip())
        else:
            data = json.loads(line)
            port = data["listening_port"]
    except (ValueError, KeyError, TypeError) as exc:
        raise InvalidWitness("SERVER_START_INVALID") from exc
    if not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535:
        raise InvalidWitness("SERVER_START_INVALID")
    return port


def _send(port: int, token: str, *, proxy: bool) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=MAX_IO_SECONDS) as conn:
            conn.settimeout(MAX_IO_SECONDS)
            if proxy:
                conn.sendall(CONNECT)
                if read_exact(conn, len(ESTABLISHED)) != ESTABLISHED:
                    return False
            conn.sendall(PREFIX + token.encode("ascii") + b"\n")
            return read_exact(conn, len(ACK)) == ACK
    except OSError:
        return False


def _spawn(command: list[str], processes: list[subprocess.Popen[bytes]]) -> subprocess.Popen[bytes]:
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            stdin=subprocess.DEVNULL, cwd=ROOT, close_fds=True)
    processes.append(proc)
    return proc


def _stop(processes: list[subprocess.Popen[bytes]]) -> None:
    for proc in reversed(processes):
        if proc.poll() is None:
            proc.terminate()
    for proc in reversed(processes):
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
        finally:
            if proc.stdout is not None:
                proc.stdout.close()


def rehearsal() -> dict[str, int | str | bool]:
    if os.name != "posix":
        raise InvalidWitness("POSIX_PRIVATE_LOG_REQUIRED")
    processes: list[subprocess.Popen[bytes]] = []
    # Files with ephemeral tokens are only created inside this private temp dir.
    with tempfile.TemporaryDirectory(prefix="apl-smart4-offline-") as directory:
        work = Path(directory)
        try:
            direct = _spawn([sys.executable, "-u", str(ROOT / "qa_smart4_egress_witness.py"),
                "listen", "--channel", "DIRECT", "--bind", "127.0.0.1",
                "--port", "0", "--output", str(work / "direct.jsonl"),
                "--duration", "15", "--max-probes", "1"], processes)
            direct_port = _read_ready(direct, b"{")
            proxy = _spawn([sys.executable, "-u", str(ROOT / "qa_smart4_egress_witness.py"),
                "listen", "--channel", "PROXY", "--bind", "127.0.0.1",
                "--port", "0", "--output", str(work / "proxy.jsonl"),
                "--duration", "15", "--max-probes", "1"], processes)
            proxy_port = _read_ready(proxy, b"{")
            relay = _spawn([sys.executable, "-u", str(ROOT / "qa_smart4_physical_proxy_relay.py"),
                "--bind", "127.0.0.1", "--port", "0", "--witness-port", str(proxy_port),
                "--duration", "15", "--max-probes", "1"], processes)
            relay_port = _read_ready(relay, b"RELAY_LISTENING_PORT=")
            first, second = secrets.token_hex(16), secrets.token_hex(16)
            issued = int(time.time() * 1000)
            # The plan is also private 0600, not just the witness receipts.
            fd = os.open(work / "intents.jsonl", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as plans:
                for route, token in (("DIRECT", first), ("PROXY", second)):
                    plans.write(json.dumps({"token": token, "route": route,
                                "issued_at_ms": issued}, separators=(",", ":")) + "\n")
            if not _send(direct_port, first, proxy=False):
                raise InvalidWitness("DIRECT_ACK_MISSING")
            if not _send(relay_port, second, proxy=True):
                raise InvalidWitness("PROXY_ACK_MISSING")
            for proc in processes:
                if proc.wait(timeout=MAX_IO_SECONDS) != 0:
                    raise InvalidWitness("WITNESS_SERVER_FAILED")
            result = verify(work / "intents.jsonl", work / "direct.jsonl",
                            work / "proxy.jsonl")
            if result.observed != 2 or result.confirmed_matches != 2 or not result.attested:
                raise InvalidWitness("WITNESS_MISMATCH")
            public = result.public()
            # Even true here is a synthetic loopback attestation only.
            public["scope"] = "synthetic_loopback_only"
            public["physical_egress_verified"] = False
            public["original_packettunnel_flow_verified"] = False
            public["cleanup"] = "automatic"
            return public
        finally:
            _stop(processes)


def main() -> int:
    try:
        print(json.dumps(rehearsal(), sort_keys=True))
        return 0
    except (InvalidWitness, OSError, subprocess.TimeoutExpired) as exc:
        code = str(exc) if isinstance(exc, InvalidWitness) else "RUNNER_FAILED"
        print("SMART4_OFFLINE_REJECTED " + code, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
