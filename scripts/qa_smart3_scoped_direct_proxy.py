#!/usr/bin/env python3
"""Explicit, temporary, no-forwarding HTTP CONNECT fixture for iPhone QA.

Requires --physical-lab; binds only the specified private IPv4 LAN address.
It NEVER connects to a destination host or authenticates a real proxy profile.
Simulates one healthy upstream host and two hanging target CONNECT sessions.
"""
from __future__ import annotations

import argparse
import ipaddress
import socketserver
import threading
import time

HEALTHY = "www.cloudflare.com:443"
FAIL = "www.apple.com:443"
START = "start.qa-example.test:80"
NEIGHBOR = "www.apple.com.cn:443"


class BoundedServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True
    request_queue_size = 16


class MockConnect(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(4)
        content = b""
        try:
            while b"\r\n\r\n" not in content and len(content) < 4096:
                chunk = self.request.recv(1024)
                if not chunk:
                    return
                content += chunk
            first = content.split(b"\r\n", 1)[0]
            if (getattr(self.server, "safari_redirect", False) and
                    first == b"CONNECT " + START.encode("ascii") + b" HTTP/1.1"):
                # Safari first loads a synthetic HTTP A, then follows a real
                # redirect to the blocked HTTPS auth-like destination. No
                # real origin connection or user account is contacted here.
                print("START_CONNECT", flush=True)
                self.request.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                request = b""
                while b"\r\n\r\n" not in request and len(request) < 4096:
                    part = self.request.recv(1024)
                    if not part:
                        return
                    request += part
                if not request.startswith(b"GET "):
                    print("START_BAD_METHOD", flush=True)
                    return
                self.request.sendall(
                    b"HTTP/1.1 302 Found\r\n"
                    b"Location: https://www.apple.com/\r\n"
                    b"Content-Length: 0\r\n"
                    b"Cache-Control: no-store\r\n"
                    b"Connection: close\r\n\r\n")
                print("START_REDIRECT_TO_TARGET", flush=True)
                time.sleep(1)
            elif (getattr(self.server, "shared_ip_qa", False) and
                  first == b"CONNECT " + NEIGHBOR.encode("ascii") + b" HTTP/1.1"):
                # A distinct hostname resolves to the same Akamai CDN IPv4
                # on the test Mac. Its traffic MUST stay with the proxy.
                print("NEIGHBOR_PROXY_CONNECT", flush=True)
                self.request.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                time.sleep(2)
            elif first == b"CONNECT " + HEALTHY.encode("ascii") + b" HTTP/1.1":
                print("HEALTHY_CONNECT", flush=True)
                self.request.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                time.sleep(2)
            elif first == b"CONNECT " + FAIL.encode("ascii") + b" HTTP/1.1":
                print("BLOCKED_CONNECT", flush=True)
                time.sleep(13.8)  # The engine must reach its 12-second deadline.
            else:
                print("DENIED_UNEXPECTED_CONNECT", flush=True)
                self.request.sendall(b"HTTP/1.1 403 Forbidden\r\n\r\n")
        except OSError:
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--physical-lab", action="store_true")
    parser.add_argument("--safari-redirect", action="store_true",
                        help="Enable a synthetic HTTP 302 start-site fixture")
    parser.add_argument("--shared-ip-qa", action="store_true",
                        help="Observe a distinct proxy-only hostname sharing Apple's CDN IPv4")
    parser.add_argument("--bind-ip", default="192.168.1.80")
    parser.add_argument("--port", type=int, default=18081)
    options = parser.parse_args()
    if not options.physical_lab:
        parser.error("Lab is opt-in only. Supply --physical-lab.")
    address = ipaddress.ip_address(options.bind_ip)
    if not isinstance(address, ipaddress.IPv4Address) or not address.is_private:
        parser.error("Only explicit private IPv4 LAN binding is permitted.")
    if options.port != 18081:
        parser.error("This fixed-purpose fixture may only use port 18081.")
    with BoundedServer((str(address), options.port), MockConnect) as server:
        server.safari_redirect = options.safari_redirect
        server.shared_ip_qa = options.shared_ip_qa
        threading.Timer(115, server.shutdown).start()
        print("READY_SCOPED_MOCK lifetime<=115s no_forwarding=true", flush=True)
        server.serve_forever(poll_interval=0.1)


if __name__ == "__main__":
    main()
