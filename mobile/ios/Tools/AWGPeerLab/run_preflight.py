#!/usr/bin/env python3
"""Synthetic separate-process AWG TCP/UDP preflight on fixed lab LAN only."""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import tempfile
import time

LAB_IP = "192.168.1.80"


def keypair():
    private = subprocess.check_output(["openssl", "genpkey", "-algorithm", "X25519", "-outform", "DER"], timeout=5)
    public = subprocess.check_output(["openssl", "pkey", "-inform", "DER", "-pubout", "-outform", "DER"], input=private, timeout=5)
    assert len(private) == 48 and private.startswith(bytes.fromhex("302e020100300506032b656e04220420"))
    assert len(public) == 44 and public.startswith(bytes.fromhex("302a300506032b656e032100"))
    return private[-32:].hex(), public[-32:].hex()


def run_case(binary, root, mode, bridge=None):
    a, ap = keypair()
    b, bp = keypair()
    _, wrong = keypair()
    psk, nonce = secrets.token_hex(32), secrets.token_hex(24)
    common = {"Nonce": nonce, "ClientIP": LAB_IP}
    server = root / (mode + "-server.json")
    client = root / (mode + "-client.json")
    server.write_text(json.dumps(dict(common, Private=b, Peer=ap, PSK=psk)))
    client.write_text(json.dumps(dict(common, Private=a, Peer=wrong if mode == "wrong-key" else bp,
                                      PSK=secrets.token_hex(32) if mode == "wrong-psk" else psk)))
    log = root / (mode + "-server.log")
    with log.open("w") as f:
        peer = subprocess.Popen([str(binary), "server", str(server)], stdout=f, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while "AWG_PEER_READY" not in log.read_text():
                assert peer.poll() is None and time.monotonic() < deadline, "peer readiness failed"
                time.sleep(.05)
            # Reject UDP from a source port other than the owned client.
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.bind((LAB_IP, 0))
                assert s.getsockname()[1] != 39890
                s.sendto(b"APL synthetic foreign source", (LAB_IP, 39891))
            cmd = [str(bridge), "--synthetic-lan-bridge-probe", str(client)] if mode == "bridge" else [str(binary), "positive" if mode == "positive" else "negative", str(client)]
            result = subprocess.run(cmd,
                                    capture_output=True, text=True, timeout=15)
            print(mode, result.stdout.strip(), flush=True)
            assert result.returncode == 0, "client failed"
        finally:
            Path(str(server) + ".stop").touch()
            try:
                peer.wait(timeout=6)
            except subprocess.TimeoutExpired:
                peer.terminate()
                try:
                    peer.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    peer.kill()
                    peer.wait(timeout=3)
    assert peer.returncode == 0, "peer failed to close"
    measured = re.search(r"AWG_WITNESS tcp4=(\d+) tcp6=(\d+) udp4=(\d+) udp6=(\d+) sent=(\d+) received=(\d+) rejected=(\d+)", log.read_text())
    assert measured, "missing witness"
    counts = tuple(map(int, measured.groups()))
    assert counts[:4] == ((1, 1, 1, 1) if mode == "positive" else (0, 0, 1, 1) if mode == "bridge" else (0, 0, 0, 0)), "unexpected receipt counts"
    assert counts[5] > 0 and counts[6] > 0, "no transport/rejection evidence"
    if mode in ("positive", "bridge"):
        assert counts[4] > 0
    print(mode, "WITNESS", counts, "PASS", flush=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--peer", type=Path, required=True)
    p.add_argument("--bridge", type=Path)
    args = p.parse_args()
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="apl-awg-separate-peer-") as d:
        for mode in ("positive", "wrong-key", "wrong-psk"):
            run_case(args.peer.resolve(), Path(d), mode)
        if args.bridge:
            run_case(args.peer.resolve(), Path(d), "bridge", args.bridge.resolve())
    print("AWG_SEPARATE_PROCESS_PREFLIGHT_PASS", flush=True)


if __name__ == "__main__":
    main()
