#!/usr/bin/env python3
"""Supervised isolated AWG QA only. Never stop or install the owner's APL.
Requires separately approved development signing, explicit device permission,
and a prior OFF observation. No automatic installation or VPN restoration.
"""
import argparse
import base64
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import tempfile
import time
import uuid
from run_preflight import keypair, LAB_IP
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from native_control_receipt import validate_native_control

DEVICE = "00008110-001C51810A12401E"
APP = "ru.arvectum.proxylauncher.lab.nativeqa"
KINDS = ("tcp4", "tcp6", "udp4", "udp6")


def ctl(*args, check=True, timeout=12):
    return subprocess.run(["xcrun", "devicectl", "device", *args[:2], "--device", DEVICE, *args[2:]],
                          check=check, timeout=timeout, capture_output=True, text=True)


def assert_off():
    processes = ctl("info", "processes").stdout
    # Visible processes are supplementary; operator must separately verify
    # global VPN OFF before starting the suite.
    if any(x in processes for x in ("Arvectum Packet Tunnel", "NativeLab.appex", "AWGProvider.appex")):
        raise RuntimeError("Live extension: abort before start")


def read_result(root):
    out = root / "device-result.json"
    out.unlink(missing_ok=True)
    call = ctl("copy", "from", "--domain-type", "appDataContainer", "--domain-identifier", APP,
               "--source", "Documents/awg-lab-result.json", "--destination", str(out), check=False)
    if call.returncode or not out.is_file():
        return None
    try:
        if out.stat().st_size > 4096:
            return None
        item = json.loads(out.read_text())
        return item if isinstance(item, dict) else None
    except (OSError, ValueError):
        return None


def dispatch(root, request, wait=True):
    runid = str(uuid.uuid4()).upper()
    request = dict(request, runID=runid)
    fixture = root / "device-input.json"
    fixture.write_text(json.dumps(request))
    try:
        ctl("copy", "to", "--domain-type", "appDataContainer", "--domain-identifier", APP,
            "--source", str(fixture), "--destination", "Documents/awg-lab-input.json")
        ctl("process", "launch", "--terminate-existing", APP, "--", "--apl-authorized-awg-qa")
    finally:
        fixture.unlink(missing_ok=True)
    if not wait:
        return runid
    deadline = time.monotonic() + 35
    while time.monotonic() < deadline:
        item = read_result(root)
        if item and item.get("runID") == runid:
            return item
        time.sleep(.5)
    raise RuntimeError("No matching device receipt")


def cleanup(root):
    item = dispatch(root, {"action": "cleanup"})
    if item.get("cleaned") is not True:
        raise RuntimeError("Owned profile cleanup unconfirmed; do not uninstall")
    assert_off()
    print("AWG_PHYSICAL_PROFILE_CLEANED", flush=True)


def validate_receipt(item, counts, kind, mode):
    if kind not in KINDS or mode not in ("positive", "wrong-key", "wrong-psk"):
        raise RuntimeError("Unknown case")
    if item.get("connected") is not True or item.get("retainedOff") is not True:
        raise RuntimeError("Native/OS start or stop not confirmed")
    expected = tuple(int(k == kind and mode == "positive") for k in KINDS)
    if len(counts) != 7 or counts[:4] != expected or counts[5] <= 0 or item.get("receipt") is not (mode == "positive"):
        raise RuntimeError("Wrong peer witness or transport receipt")
    if mode == "positive" and counts[4] <= 0:
        raise RuntimeError("No return transport")


def case(root, peerbinary, client, kind, mode, native_control=False):
    assert_off()
    client_private, client_public = keypair()
    server_private, server_public = keypair()
    _, wrong_public = keypair()
    psk, nonce = secrets.token_hex(32), secrets.token_hex(24)
    cfg = root / "server.json"
    stop = Path(str(cfg) + ".stop")
    stop.unlink(missing_ok=True)
    cfg.write_text(json.dumps({"Private": server_private, "Peer": client_public, "PSK": psk,
                               "Nonce": nonce, "ClientIP": str(client)}))
    keys = bytes.fromhex(client_private + (wrong_public if mode == "wrong-key" else server_public)
                        + (secrets.token_hex(32) if mode == "wrong-psk" else psk))
    log = root / "server.log"
    with log.open("w") as f:
        peer = subprocess.Popen([str(peerbinary), "server", str(cfg)], stdout=f, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while "AWG_PEER_READY" not in log.read_text():
                if peer.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError("Peer readiness failed")
                time.sleep(.05)
            item = dispatch(root, {"action": "run", "keys": base64.b64encode(keys).decode(),
                                   "localIPv4": int(client), "probe": kind, "nonce": nonce, "nativeControlQA": native_control})
        finally:
            stop.touch()
            try:
                peer.wait(timeout=6)
            except subprocess.TimeoutExpired:
                peer.terminate()
                try:
                    peer.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    peer.kill()
                    peer.wait(timeout=3)
            cfg.unlink(missing_ok=True)
    if peer.returncode:
        raise RuntimeError("Peer process failed to close")
    m = re.search(r"AWG_WITNESS tcp4=(\d+) tcp6=(\d+) udp4=(\d+) udp6=(\d+) sent=(\d+) received=(\d+) rejected=(\d+)", log.read_text())
    if not m:
        raise RuntimeError("No independent witness")
    counts = tuple(map(int, m.groups()))
    validate_receipt(item, counts, kind, mode)
    if native_control:
        validate_native_control(item)
        print("AWG_NATIVE_CONTROL_RECEIPTS_PASS", flush=True)
    assert_off()
    print("AWG_PHYSICAL_CASE", kind, mode, "WITNESS", counts, "PASS", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--approved", action="store_true", required=True)
    parser.add_argument("action", choices=("prepare", "suite", "cleanup"))
    parser.add_argument("--prepared-id")
    parser.add_argument("--peer", type=Path)
    parser.add_argument("--peer-sha256")
    parser.add_argument("--client-ip")
    parser.add_argument("--native-control", action="store_true", help="One targeted TCP4 control test instead of repeating the accepted suite")
    args = parser.parse_args()
    if args.action == "suite":
        if not all((args.prepared_id, args.peer, args.peer_sha256, args.client_ip)):
            parser.error("suite requires prepared-id, peer, peer-sha256, client-ip")
        prepared_id = str(uuid.UUID(args.prepared_id)).upper()
        client = ipaddress.IPv4Address(args.client_ip)
        if client not in ipaddress.IPv4Network("192.168.1.0/24") or str(client) in (LAB_IP, "192.168.1.0", "192.168.1.255"):
            parser.error("not an isolated physical LAN client")
        peer = args.peer.resolve(strict=True)
        if hashlib.sha256(peer.read_bytes()).hexdigest() != args.peer_sha256.lower():
            parser.error("peer digest mismatch")
    os.umask(0o077)
    # Never use this runner while another lab or the owner's VPN is active.
    processes = ctl("info", "processes").stdout
    if any(x in processes for x in ("Arvectum Packet Tunnel", "NativeLab.appex")):
        raise RuntimeError("Foreign extension active; supervised OFF required")
    with tempfile.TemporaryDirectory(prefix="apl-awg-physical-") as path:
        root = Path(path)
        if args.action == "prepare":
            assert_off()
            runid = dispatch(root, {"action": "prepare"}, wait=False)
            print("AWG_PREPARE_REQUEST_ID", runid, flush=True)
            return
        if args.action == "cleanup":
            cleanup(root)
            return
        assert_off()
        receipt = read_result(root)
        if not receipt or receipt.get("runID") != prepared_id or receipt.get("prepared") is not True or receipt.get("localIPv4") != int(client):
            raise RuntimeError("Explicit prepare-only receipt missing")
        try:
            if args.native_control:
                case(root, peer, client, "tcp4", "positive", native_control=True)
            else:
                for kind in KINDS:
                    case(root, peer, client, kind, "positive")
                for mode in ("wrong-key", "wrong-psk"):
                    case(root, peer, client, "tcp4", mode)
                    case(root, peer, client, "udp4", mode)
        finally:
            cleanup(root)
        print("AWG_PHYSICAL_NATIVE_CONTROL_PASS" if args.native_control else "AWG_PHYSICAL_SUITE_PASS", flush=True)


if __name__ == "__main__":
    main()
