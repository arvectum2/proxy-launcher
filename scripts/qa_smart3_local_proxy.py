#!/usr/bin/env python3
"""Disposable, opt-in Smart 3.0 hardware QA proxy; never forwards arbitrary web traffic.

Usage: python3 scripts/qa_smart3_local_proxy.py --bind <Mac-LAN-IP> --port 18081
Requires explicit --bind, auto-stops within 115 seconds. ONLY synthetic
*.qa-example.test:443 CONNECT requests are accepted; all others rejected.
Do not run on public interfaces or use a paid/production upstream.
"""
from __future__ import annotations

import argparse
import ipaddress
import signal
import socketserver
import threading
import time


class QA(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(4)
        data = b''
        try:
            while b'\r\n\r\n' not in data and len(data) < 8192:
                chunk = self.request.recv(4096)
                if not chunk:
                    return
                data += chunk
            first = data.split(b'\r\n', 1)[0].decode('ascii', errors='replace')
            target = first.split(' ')[1] if first.startswith('CONNECT ') else ''
            if target not in {'auth.qa-example.test:443', 'probe.qa-example.test:443'}:
                self.request.sendall(b'HTTP/1.1 403 Forbidden\r\n\r\n')
                return
            print('QA_CONNECT_AUTH' if target.startswith('auth.') else 'QA_CONNECT_PROBE', flush=True)
            if target.startswith('auth.'):
                time.sleep(13.8)  # Rust CONNECT timeout is 12 seconds.
            else:
                self.request.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
                time.sleep(2)
        except (OSError, UnicodeError):
            pass


class Server(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bind', required=True)
    parser.add_argument('--port', type=int, default=18081)
    args = parser.parse_args()
    address = ipaddress.ip_address(args.bind)
    if address.version != 4 or address.is_unspecified or address.is_global or args.port != 18081:
        parser.error('bind must be private/loopback IPv4 and port exactly 18081')
    with Server((args.bind, args.port), QA) as server:
        threading.Timer(115, server.shutdown).start()
        print('QA_PROXY_READY: expires <=115s, no upstream forwarding', flush=True)
        server.serve_forever(poll_interval=0.1)


if __name__ == '__main__':
    main()
