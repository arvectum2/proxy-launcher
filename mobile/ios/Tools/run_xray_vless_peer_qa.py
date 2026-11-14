#!/usr/bin/env python3
"""Synthetic localhost-only VLESS peers and independent nonce witness."""
import argparse
import base64
import contextlib
import http.server
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import threading
import time
import uuid

HOST = "127.0.0.1"
RECEIPT_HOST = "apl-receipt.invalid"
SERVER_PORT = 39882
WITNESS_PORT = 39883
DECOY_PORT = 39884
CLIENT_PORT = 39879


def keypair():
    private = subprocess.check_output(["openssl", "genpkey", "-algorithm", "X25519", "-outform", "DER"])
    public = subprocess.check_output(["openssl", "pkey", "-inform", "DER", "-pubout", "-outform", "DER"], input=private)
    assert private.startswith(bytes.fromhex("302e020100300506032b656e04220420")) and len(private) == 48
    assert public.startswith(bytes.fromhex("302a300506032b656e032100")) and len(public) == 44
    encode = lambda value: base64.urlsafe_b64encode(value[-32:]).decode().rstrip("=")
    return encode(private), encode(public)


def wait_for(process, path, marker, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if marker in path.read_text(errors="replace"):
            return
        if process.poll() is not None:
            break
        time.sleep(.05)
    markers = [line for line in path.read_text(errors="replace").splitlines()
               if line.startswith("PEER_QA_FAILED_")]
    raise RuntimeError("lab not ready: " + ",".join(markers))


def check_port_free(port):
    with socket.socket() as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((HOST, port))


def run(sim, binary, host_server, directory, tun=False, cycles=False):
    for port in range(CLIENT_PORT, DECOY_PORT + 1):
        check_port_free(port)
    private, public = keypair()
    _, wrong_public = keypair()
    ids = [str(uuid.uuid4()), str(uuid.uuid4())]
    sid = secrets.token_hex(8)
    nonce_paths = {name: "/" + secrets.token_hex(20) for name in
                   ("no_vision", "vision", "bad_uuid", "bad_key", "stopped")}
    cycle_paths = ["/" + secrets.token_hex(20) for _ in range(12)] if cycles else []
    allowed = set(nonce_paths.values()) | set(cycle_paths)
    seen = []
    lock = threading.Lock()

    class Witness(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path not in allowed:
                self.send_error(404); return
            with lock:
                seen.append(self.path)
            reply = ("APL_RECEIPT:" + self.path[1:]).encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(reply)))
            self.end_headers()
            self.wfile.write(reply)

        def log_message(self, *_):
            pass

    server_config = {
        "log": {"loglevel": "none"},
        "inbounds": [{"tag": "qa-in", "listen": HOST, "port": SERVER_PORT,
                      "protocol": "vless", "settings": {
                          "clients": [{"id": ids[0]}, {"id": ids[1], "flow": "xtls-rprx-vision"}],
                          "decryption": "none"},
                      "streamSettings": {"network": "raw", "security": "reality",
                          "realitySettings": {"target": f"{HOST}:{DECOY_PORT}",
                              "serverNames": ["example.com"], "privateKey": private,
                              "shortIds": [sid]}}}],
        "outbounds": [{"tag": "deny", "protocol": "blackhole"},
                      {"tag": "receipt-only", "protocol": "freedom",
                       "settings": {"redirect": f"{HOST}:{WITNESS_PORT}",
                           "finalRules": [
                               {"action": "allow", "network": "tcp", "port": str(WITNESS_PORT),
                                "ip": ["127.0.0.1/32"]},
                               {"action": "block"}
                           ]}}],
        "routing": {"domainStrategy": "AsIs", "rules": [
            {"type": "field", "inboundTag": ["qa-in"],
             "domain": ["full:" + RECEIPT_HOST], "port": str(WITNESS_PORT),
             "network": "tcp", "outboundTag": "receipt-only"}]}
    }
    if tun or cycles:
        # Synthetic TEST-NET-2 target only, never accessed on the underlay.
        server_config["routing"]["rules"].append({
            "type": "field", "inboundTag": ["qa-in"], "ip": ["198.51.100.77/32"],
            "port": str(WITNESS_PORT), "network": "tcp", "outboundTag": "receipt-only"})
    config = directory / "server.json"
    config.write_text(json.dumps(server_config))
    cert, key = directory / "tls.crt", directory / "tls.key"
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048",
                    "-nodes", "-keyout", str(key), "-out", str(cert),
                    "-days", "1", "-subj", "/CN=example.com"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    @contextlib.contextmanager
    def peer(role, fixture, port):
        log = directory / (fixture.stem + ".log")
        with log.open("w") as output:
            command = ([str(host_server)] if role == "server" else
                       ["xcrun", "simctl", "spawn", sim, str(binary)])
            proc = subprocess.Popen(command + [role, str(fixture), str(port)],
                                    stdout=output, stderr=subprocess.STDOUT)
            try:
                wait_for(proc, log, "PEER_QA_READY_" + role)
                yield
            finally:
                Path(str(fixture) + ".stop").touch()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.terminate()
                    proc.wait(timeout=4)
                if proc.returncode != 0 or "PEER_QA_STOPPED_" + role not in log.read_text(errors="replace"):
                    raise RuntimeError("peer stop not confirmed: " + role)

    def probe(name, uid, pub, vision, expected):
        fixture = directory / (name + ".uri")
        fixture.write_text(f"vless://{uid}@{HOST}:{SERVER_PORT}?encryption=none&security=reality&type=tcp"
                           f"&sni=example.com&fp=chrome&pbk={pub}&sid={sid}"
                           + ("&flow=xtls-rprx-vision" if vision else ""))
        path = nonce_paths[name]
        if tun:
            Path(str(fixture) + ".path").write_text(path)
            result = subprocess.run(
                ["xcrun", "simctl", "spawn", sim, str(binary), "tun-client",
                 str(fixture), str(CLIENT_PORT)],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=25, text=True)
            markers = [line for line in result.stdout.splitlines()
                       if line.startswith(("TUN_QA_", "PEER_QA_"))]
            for line in markers:
                print(line, flush=True)
            if (result.returncode != 0 or "TUN_QA_RUST_DRAINED_DESCRIPTOR_CLOSED" not in markers
                    or "TUN_QA_SYNACK" not in markers
                    or markers.count("TUN_QA_RECEIPT_true") + markers.count("TUN_QA_RECEIPT_false") != 1
                    or "TUN_QA_RUST_EXIT_0" not in markers
                    or "PEER_QA_STOPPED_tun-client" not in markers):
                raise RuntimeError("native TUN lifecycle failed: " + name)
            ok = "TUN_QA_RECEIPT_true" in markers
            with lock:
                count = seen.count(path)
            if ok != expected or count != int(expected):
                raise RuntimeError(f"TUN probe {name}: response={ok} witness_count={count}")
            print(f"APL_TUN_VLESS_{name.upper()}_RESPONSE_{ok}_WITNESS_{count}_PASS", flush=True)
            check_port_free(CLIENT_PORT)
            return
        with peer("client", fixture, CLIENT_PORT):
            result = subprocess.run(
                ["curl", "--disable", "--noproxy", "", "--silent", "--show-error",
                 "--max-time", "7", "--socks5-hostname", f"{HOST}:{CLIENT_PORT}",
                 f"http://{RECEIPT_HOST}:{WITNESS_PORT}{path}"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                env={k: v for k, v in os.environ.items() if "proxy" not in k.lower()})
            ok = result.returncode == 0 and result.stdout == ("APL_RECEIPT:" + path[1:]).encode()
            with lock:
                count = seen.count(path)
            if ok != expected or count != int(expected):
                print("CURL_RC", result.returncode, flush=True)
                raise RuntimeError(f"probe {name}: response={ok} witness_count={count}")
            print(f"APL_VLESS_PEER_{name.upper()}_RESPONSE_{ok}_WITNESS_{count}_PASS", flush=True)
        check_port_free(CLIENT_PORT)

    def repeated_cycles():
        fixture = directory / "cycles.uri"
        fixture.write_text(f"vless://{ids[0]}@{HOST}:{SERVER_PORT}?encryption=none&security=reality&type=tcp"
                           f"&sni=example.com&fp=chrome&pbk={public}&sid={sid}")
        Path(str(fixture) + ".path").write_text("\n".join(cycle_paths))
        result = subprocess.run(
            ["xcrun", "simctl", "spawn", sim, str(binary), "tun-cycles", str(fixture), str(CLIENT_PORT)],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=65, text=True)
        markers = [line for line in result.stdout.splitlines()
                   if line.startswith(("TUN_QA_", "PEER_QA_"))]
        for line in markers:
            print(line, flush=True)
        if (result.returncode != 0
                or markers.count("TUN_QA_SYNACK") != 12
                or markers.count("TUN_QA_RUST_EXIT_0") != 12
                or markers.count("TUN_QA_RUST_DRAINED_DESCRIPTOR_CLOSED") != 12
                or any(markers.count(f"TUN_QA_CYCLE_PASS_{n}") != 1 for n in range(1,13))
                or "PEER_QA_STOPPED_tun-cycles" not in markers):
            print("TUN_QA_PROCESS_RC", result.returncode, flush=True)
            import re
            for line in result.stdout.splitlines():
                if re.search(r"panic:|fatal error:|SIG[A-Z]+|EXC_|signal [0-9]+|killed|crash|runtime\.|error was encountered|exit status|launchd|NSPOSIXErrorDomain|CoreSimulator", line, re.I):
                    print("TUN_QA_DIAG", re.sub(r"[A-Za-z0-9_-]{24,}", "[redacted]", line)[:250], flush=True)
            raise RuntimeError("same-process lifecycle not confirmed")
        with lock:
            if sorted(seen) != sorted(cycle_paths):
                raise RuntimeError("same-process independent witness count mismatch")
        check_port_free(CLIENT_PORT)
        print("APL_TUN_SAME_PROCESS_TWELVE_CYCLES_EXACT_WITNESSES_PASS", flush=True)

    witness = http.server.ThreadingHTTPServer((HOST, WITNESS_PORT), Witness)
    worker = threading.Thread(target=witness.serve_forever, daemon=True)
    worker.start()
    decoy = subprocess.Popen(["openssl", "s_server", "-accept", f"{HOST}:{DECOY_PORT}",
                              "-cert", str(cert), "-key", str(key), "-tls1_3",
                              "-alpn", "h2,http/1.1", "-www", "-quiet"],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
    try:
        time.sleep(.3)
        if decoy.poll() is not None:
            raise RuntimeError("decoy not started")
        if cycles:
            with peer("server", config, SERVER_PORT):
                repeated_cycles()
            check_port_free(SERVER_PORT)
        else:
            with peer("server", config, SERVER_PORT):
                probe("no_vision", ids[0], public, False, True)
                probe("vision", ids[1], public, True, True)
                probe("bad_uuid", str(uuid.uuid4()), public, False, False)
                probe("bad_key", ids[0], wrong_public, False, False)
            check_port_free(SERVER_PORT)
            probe("stopped", ids[0], public, False, False)
            with lock:
                assert sorted(seen) == sorted([nonce_paths["no_vision"], nonce_paths["vision"]])
            print(("APL_TUN_VLESS" if tun else "APL_VLESS_PEER") + "_2_AUTHENTICATED_3_NEGATIVE_EXACT_WITNESSES_PASS", flush=True)
    finally:
        decoy.terminate()
        decoy.wait(timeout=3)
        witness.shutdown()
        witness.server_close()
        worker.join(timeout=3)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--host-server", required=True, type=Path)
    parser.add_argument("--tun", action="store_true")
    parser.add_argument("--cycles", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="apl-xray-peer-") as tmp:
        run(args.simulator, args.binary.resolve(), args.host_server.resolve(), Path(tmp), tun=args.tun, cycles=args.cycles)
