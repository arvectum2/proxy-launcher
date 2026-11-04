#!/usr/bin/env python3
"""Controlled live TCP proof of why IP-wide NE bypass leaks on shared CDNs.

Origin and fake proxy run on loopback with two different Host names on the
*same real socket IP*. This is not an end-to-end iOS Packet Tunnel test. The
route algorithm is a duplicate test model; canonical Swift guard is tested
independently with swift test/SharedIPRouteGuardTests.
"""
from __future__ import annotations

import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread


class Origin(BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.requests.append((self.headers.get('Host'), self.path))
        body = (b'<html><script src="http://api.site.test/script.js"></script>'
                b'<link href="http://static.site.test/style.css" rel="stylesheet"></html>'
                if self.path == '/' else b'asset or API data')
        self.send_response(200)
        self.send_header('X-APL-Test-Egress', 'DIRECT')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class MockProxy(Origin):
    def do_GET(self):
        self.server.requests.append((self.headers.get('Host'), self.path))
        body = b'PROXY-PATH'
        self.send_response(200)
        self.send_header('X-APL-Test-Egress', 'PROXY')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def test_network():
    origin = ThreadingHTTPServer(('127.0.0.1', 0), Origin)
    proxy = ThreadingHTTPServer(('127.0.0.1', 0), MockProxy)
    for server in (origin, proxy):
        server.requests = []
        Thread(target=server.serve_forever, daemon=True).start()

    def connect(server, domain, path):
        client = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
        try:
            client.request('GET', path, headers={'Host': domain})
            response = client.getresponse()
            assert response.status == 200
            egress = response.getheader('X-APL-Test-Egress')
            data = response.read()
            return egress, data
        finally:
            client.close()

    try:
        approved = {'site.test', 'api.site.test', 'static.site.test'}
        denied = {'tracker.site.test'}
        addresses = {name: '127.0.0.1' for name in approved | denied}
        assert len(set(addresses.values())) == 1, 'Hostnames must share a real destination IP'
        # Demonstrate current IP-wide excludedRoutes hazard: every host on
        # this IP takes the DIRECT route, including the unapproved tracker.
        baseline = [(h, connect(origin, h, '/')[0]) for h in sorted(approved | denied)]
        assert all(egress == 'DIRECT' for _, egress in baseline)
        print('IP_WIDE_BASELINE_TRACKER_LEAK_CONFIRMED', baseline, flush=True)

        # A known pending/rejected host collides: the Swift guard withholds the
        # overlapping real IP from NE excludedRoutes and from virtual DNS
        # host mappings. No domain is routed DIRECT for this shared IP.
        allowed_ips = set(addresses[h] for h in approved)
        known_denied_ips = set(addresses[h] for h in denied)
        safe_ips = allowed_ips - known_denied_ips
        assert not safe_ips
        routed = [(h, connect(origin if addresses[h] in safe_ips else proxy, h, '/')[0])
                  for h in sorted(approved | denied)]
        assert all(egress == 'PROXY' for _, egress in routed)
        print('KNOWN_SHARED_IP_FAIL_CLOSED_CONFIRMED', routed, flush=True)

        # When no rejected host uses the approved address, a connected first-
        # party resource can still use the real DIRECT path as designed.
        allowed_hosts = sorted(approved)
        for host in allowed_hosts:
            egress, payload = connect(origin, host, '/api' if host != 'site.test' else '/')
            assert egress == 'DIRECT' and payload
        print('DEPENDENT_FIRST_PARTY_HTML_API_CSS_DIRECT_SOCKET_OK', allowed_hosts, flush=True)
        assert (denied.pop(), '/api') not in origin.requests
        assert len(origin.requests) >= 7 and len(proxy.requests) == 4
        return 0
    finally:
        origin.shutdown()
        proxy.shutdown()
        origin.server_close()
        proxy.server_close()


if __name__ == '__main__':
    raise SystemExit(test_network())
