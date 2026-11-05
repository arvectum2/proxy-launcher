"""Smart4 physical transport QA is a synthetic sidecar, never an APL tunnel test."""
from __future__ import annotations
import contextlib
import io
import os
from pathlib import Path
import secrets
import socket
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import qa_smart4_egress_witness as witness
import qa_smart4_physical_proxy_relay as relay

class Smart4FixedProxyRelayTests(unittest.TestCase):
    def test_fixed_connect_rejects_arbitrary_forwarding(self):
        client, server = socket.socketpair()
        with client, server:
            invalid = b"CONNECT some-public-host.invalid:443 HTTP/1.1\r\n\r\n"
            client.sendall(invalid.ljust(len(relay.CONNECT), b"x"))
            with mock.patch.object(relay.socket, 'create_connection',
                                   side_effect=AssertionError('UNSAFE_FORWARD')):
                self.assertFalse(relay.relay_one(server, 18442))

    def test_invalid_token_cannot_be_relied(self):
        client, server = socket.socketpair()
        with client, server:
            client.sendall(relay.CONNECT)
            client.sendall((witness.PREFIX + b"not-a-valid-token" + b"\n")
                           .ljust(witness.FRAME_BYTES, b"x"))
            self.assertFalse(relay.relay_one(server, 18442))
            self.assertEqual(client.recv(len(relay.ESTABLISHED)), relay.ESTABLISHED)

    def test_restrict_bind_and_proxy_configuration(self):
        with self.assertRaises(witness.InvalidWitness):
            relay.serve("0.0.0.0", 0, 18442, duration=1)
        with self.assertRaises(witness.InvalidWitness):
            relay.serve("8.8.8.8", 0, 18442, duration=1)
        with self.assertRaises(witness.InvalidWitness):
            relay.serve("127.0.0.1", 0, 18442, duration=121)
        with self.assertRaises(witness.InvalidWitness):
            relay.serve("127.0.0.1", 0, 18442, duration=1, max_probes=257)

    @unittest.skipUnless(os.name == 'posix', 'Private TCP witness needs POSIX mode 0600')
    def test_actual_loopback_fixed_connect_reaches_positive_proxy_witness(self):
        with tempfile.TemporaryDirectory(prefix='smart4-relay-') as d:
            path = Path(d) / 'proxy-log.jsonl'
            upstream = witness.LabWitnessListener('PROXY', '127.0.0.1', 0, path,
                                                   max_probes=1, duration=3)
            upstream_thread = threading.Thread(target=upstream.serve, daemon=True)
            upstream_thread.start()
            with socket.socket() as port_socket:
                port_socket.bind(('127.0.0.1', 0))
                port = port_socket.getsockname()[1]
            outcome = []
            def run_relay():
                with contextlib.redirect_stdout(io.StringIO()):
                    outcome.append(relay.serve('127.0.0.1', port,
                                              upstream.bound_port, duration=3))
            t = threading.Thread(target=run_relay, daemon=True)
            t.start()
            token = secrets.token_hex(16)
            client = None
            for _ in range(30):
                try:
                    client = socket.create_connection(('127.0.0.1', port), timeout=0.25)
                    break
                except OSError:
                    time.sleep(0.02)
            self.assertIsNotNone(client)
            with client:
                client.settimeout(3)
                client.sendall(relay.CONNECT)
                self.assertEqual(relay.read_exact(client, len(relay.ESTABLISHED)),
                                 relay.ESTABLISHED)
                client.sendall(witness.PREFIX + token.encode('ascii') + b'\n')
                self.assertEqual(relay.read_exact(client, len(witness.ACK)), witness.ACK)
            t.join(4)
            upstream_thread.join(4)
            self.assertEqual(outcome, [(1, 1)])
            self.assertFalse(t.is_alive())
            self.assertFalse(upstream_thread.is_alive())
            self.assertIn(token, path.read_text())
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

class Smart4PhysicalSidecarSourceContract(unittest.TestCase):
    def test_no_production_tunnel_or_personal_data_access(self):
        qa = (ROOT / 'mobile/ios/HardwareQA/QRDeviceQA/App/Smart4TransportPhysicalQA.swift').read_text()
        config = (ROOT / 'mobile/ios/HardwareQA/QRDeviceQA/project.yml').read_text()
        self.assertIn('#if DEBUG', qa)
        self.assertIn('-aplSmart4PhysicalTransportQA', qa)
        self.assertIn('SmartFlowRoutingPolicy(', qa)
        self.assertIn('direct.qa.example.com', qa)
        self.assertIn('proxy.qa.example.com', qa)
        self.assertIn('params.requiredInterfaceType = .wifi', qa)
        self.assertIn('PacketTunnel NOT VERIFIED', qa)
        implementation = '\n'.join(line for line in qa.splitlines()
                                   if not line.lstrip().startswith('//'))
        for forbidden in ('UserDefaults', 'Keychain', 'SecItem', 'NEPacketTunnelProvider',
                          'setTunnelNetworkSettings', 'TelemetryStore', 'ProxyStore',
                          'ProfileStore', 'systemProxy', 'Credential'):
            self.assertNotIn(forbidden, implementation)
        self.assertIn('PRODUCT_BUNDLE_IDENTIFIER: ru.arvectum.qrdeviceqa.device', config)
        self.assertIn('INFOPLIST_KEY_NSLocalNetworkUsageDescription', config)
        self.assertNotIn('com.apple.security.application-groups', config)
        self.assertNotIn('com.apple.developer.networking.networkextension', config)

    def test_fixed_local_proxy_is_not_general_purpose(self):
        source = (ROOT / 'scripts/qa_smart4_physical_proxy_relay.py').read_text()
        self.assertIn('CONNECT apl-smart4-proxy.invalid:443', source)
        self.assertIn('127.0.0.1', source)
        self.assertIn('read_exact(client, len(CONNECT)) != CONNECT', source)
        self.assertIn('MAX', (ROOT / 'scripts/qa_smart4_egress_witness.py').read_text())
        for unsafe in ('http.server', 'socketserver.ThreadingTCPServer',
                       'requests.get(', 'subprocess.run(', 'Authorization:',
                       'UserDefaults', 'Logger(', 'SecItem'):
            self.assertNotIn(unsafe, source)

    def test_physical_qa_does_not_claim_smart4_tunnel_attribution(self):
        report = ROOT / 'docs/APL_IOS_SMART4_PHYSICAL_EGRESS_2026-11-05.md'
        if report.exists():
            text = report.read_text()
            self.assertIn('PacketTunnel', text)
            self.assertIn('не доказан', text)
