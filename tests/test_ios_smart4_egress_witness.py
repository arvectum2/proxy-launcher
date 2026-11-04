"""Real TCP receipts and adversarial tests for isolated Smart4 witness QA."""
from pathlib import Path
import json
import os
import secrets
import socket
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import qa_smart4_egress_witness as w

class Smart4EgressWitnessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="smart4-lab-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.issued = int(time.time() * 1000) - 10
        self.nonce = secrets.token_hex(16)

    def file(self, name, records):
        path = self.base / name
        path.write_text("".join(json.dumps(item, separators=(",", ":")) + "\n" for item in records))
        return path

    def fixture(self, *, route="DIRECT", direct=None, proxy=None, intents=None):
        plans = intents if intents is not None else [
            {"token": self.nonce, "route": route, "issued_at_ms": self.issued}]
        return (self.file("intents.jsonl", plans),
                self.file("direct.jsonl", direct or []),
                self.file("proxy.jsonl", proxy or []))

    def receipt(self, token=None, delta=1):
        return {"token": token or self.nonce, "received_at_ms": self.issued + delta}

    @unittest.skipUnless(os.name == "posix", "Private TCP witnesses require POSIX file permissions")
    def test_real_tcp_loopback_two_independent_listeners(self):
        first, second = secrets.token_hex(16), secrets.token_hex(16)
        issued = int(time.time() * 1000)
        intents = self.file("intents.jsonl", [
            {"token": first, "route": "DIRECT", "issued_at_ms": issued},
            {"token": second, "route": "PROXY", "issued_at_ms": issued}])
        direct, proxy = self.base / "direct.jsonl", self.base / "proxy.jsonl"
        a = w.LabWitnessListener("DIRECT", "127.0.0.1", 0, direct, duration=3, max_probes=1)
        b = w.LabWitnessListener("PROXY", "127.0.0.1", 0, proxy, duration=3, max_probes=1)
        ta = threading.Thread(target=a.serve, daemon=True)
        tb = threading.Thread(target=b.serve, daemon=True)
        ta.start(); tb.start()
        for server, token in ((a, first), (b, second)):
            with socket.create_connection(("127.0.0.1", server.bound_port), timeout=2) as sock:
                sock.sendall(w.PREFIX + token.encode("ascii") + b"\n")
                self.assertEqual(sock.recv(len(w.ACK)), w.ACK)
        ta.join(4); tb.join(4)
        self.assertFalse(ta.is_alive())
        self.assertFalse(tb.is_alive())
        self.assertEqual(direct.stat().st_mode & 0o777, 0o600)
        result = w.verify(intents, direct, proxy)
        self.assertEqual((result.confirmed_matches, result.confirmed_direct,
                          result.confirmed_proxy), (2, 1, 1))
        self.assertTrue(result.attested)
        public = json.dumps(result.public())
        for private in (first, second, "127.0.0.1", "host", "password", "username"):
            self.assertNotIn(private, public)

    def test_lab_positive_is_not_a_physical_iphone_proof(self):
        # A single direct proof is insufficient even for the two-route lab gate.
        result = w.verify(*self.fixture(direct=[self.receipt()]))
        self.assertEqual(result.confirmed_matches, 1)
        self.assertFalse(result.attested)
        self.assertEqual(result.public()["scope"], "synthetic_lab_only")
        self.assertIs(result.public()["physical_egress_verified"], False)

    def test_cli_rejects_inconclusive_without_exposing_token(self):
        import contextlib
        import io
        paths = self.fixture()
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            result = w.main(["verify", "--intents", str(paths[0]),
                             "--direct", str(paths[1]), "--proxy", str(paths[2])])
        self.assertEqual(result, 2)
        self.assertNotIn(self.nonce, out.getvalue())
        self.assertIn('"physical_egress_verified": false', out.getvalue())

    def test_wrong_route_is_mismatch(self):
        result = w.verify(*self.fixture(proxy=[self.receipt()]))
        self.assertEqual(result.confirmed_mismatches, 1)
        self.assertEqual(result.confirmed_matches, 0)
        self.assertFalse(result.attested)

    def test_missing_proof_never_infers_route(self):
        result = w.verify(*self.fixture())
        self.assertEqual(result.inconclusive, 1)
        self.assertFalse(result.attested)

    def test_both_observers_conflict(self):
        result = w.verify(*self.fixture(direct=[self.receipt()], proxy=[self.receipt()]))
        self.assertEqual((result.inconclusive, result.ambiguous, result.confirmed_matches), (1, 1, 0))
        self.assertFalse(result.attested)

    def test_duplicate_receipt_fails_closed(self):
        result = w.verify(*self.fixture(direct=[self.receipt(), self.receipt(delta=2)]))
        self.assertEqual((result.inconclusive, result.ambiguous), (1, 1))
        self.assertFalse(result.attested)

    def test_stale_future_and_replayed_receipts_never_confirm(self):
        for delta in (-1, w.MAX_DELAY_MS + 1):
            with self.subTest(delta=delta):
                self.assertFalse(w.verify(*self.fixture(direct=[self.receipt(delta=delta)])).attested)
        self.assertFalse(w.verify(*self.fixture(direct=[self.receipt()]),
            now_ms=self.issued + w.MAX_AGE_MS + 2).attested)

    def test_unknown_receipt_and_duplicate_intent_are_rejected(self):
        with self.assertRaisesRegex(w.InvalidWitness, "UNEXPECTED_RECEIPT"):
            w.verify(*self.fixture(direct=[self.receipt(token=secrets.token_hex(16))]))
        plan = {"token": self.nonce, "route": "DIRECT", "issued_at_ms": self.issued}
        with self.assertRaisesRegex(w.InvalidWitness, "DUPLICATE_INTENT"):
            w.verify(*self.fixture(intents=[plan, plan]))

    def test_dns_ip_guess_and_user_fields_cannot_be_witness(self):
        inferred = {**self.receipt(), "resolved_ip": "203.0.113.42"}
        with self.assertRaisesRegex(w.InvalidWitness, "INVALID_SCHEMA"):
            w.verify(*self.fixture(direct=[inferred]))
        with self.assertRaisesRegex(w.InvalidWitness, "INVALID_SCHEMA"):
            w.verify(*self.fixture(intents=[{**{"token": self.nonce, "route": "DIRECT",
                 "issued_at_ms": self.issued}, "hostname": "sensitive.invalid"}]))

    def test_invalid_route_and_timestamp_fail_closed(self):
        for bad in ("IP-INFERRED", "unknown", "DIRECT_FROM_DNS", "INVALID"):
            with self.subTest(bad=bad), self.assertRaisesRegex(w.InvalidWitness, "INVALID_ROUTE"):
                w.verify(*self.fixture(route=bad))
        with self.assertRaisesRegex(w.InvalidWitness, "INVALID_TIMESTAMP"):
            w.verify(*self.fixture(direct=[{**self.receipt(), "received_at_ms": True}]))
        with self.assertRaisesRegex(w.InvalidWitness, "INVALID_TOKEN"):
            w.verify(*self.fixture(direct=[{**self.receipt(), "token": "example.com"}]))

    def test_input_is_bounded_and_no_empty_attestation(self):
        self.assertFalse(w.verify(*self.fixture(intents=[])).attested)
        intents = [{"token": f"{i:032x}", "route": "DIRECT", "issued_at_ms": self.issued}
                   for i in range(w.MAX_PROBES + 1)]
        with self.assertRaisesRegex(w.InvalidWitness, "INPUT_LIMIT"):
            w.verify(*self.fixture(intents=intents))
        path = self.file("direct.jsonl", [])
        path.write_text("{" + "x" * 50000 + "}\n")
        with self.assertRaisesRegex(w.InvalidWitness, "INPUT_LIMIT"):
            w.verify(self.base / "intents.jsonl", path, self.base / "proxy.jsonl")

    def test_no_listening_on_public_or_wildcard_without_opt_in(self):
        for host in ("0.0.0.0", "8.8.8.8", "203.0.113.45", "192.168.0.12", "localhost"):
            with self.subTest(host=host), self.assertRaises(w.InvalidWitness):
                w.safe_bind(host, False)
        w.safe_bind("127.0.0.1", False)
        w.safe_bind("::1", False)
        w.safe_bind("192.168.0.12", True)
        with self.assertRaises(w.InvalidWitness):
            w.safe_bind("8.8.8.8", True)
        with self.assertRaises(w.InvalidWitness):
            w.LabWitnessListener("DIRECT", "127.0.0.1", 0, self.base / "x",
                                  duration=w.MAX_DURATION + 1)

    def test_nonposix_listener_is_refused_before_network_or_file_creation(self):
        from unittest.mock import patch
        target = self.base / "private-log.jsonl"
        with patch.object(w.os, "name", "nt"):
            with self.assertRaisesRegex(w.InvalidWitness, "POSIX_PRIVATE_LOG_REQUIRED"):
                w.LabWitnessListener("DIRECT", "127.0.0.1", 0, target)
        self.assertFalse(target.exists())

    def test_no_observer_file_overwrite(self):
        f = self.file("existing.jsonl", [])
        with self.assertRaisesRegex(w.InvalidWitness, "OUTPUT_ALREADY_EXISTS"):
            w.LabWitnessListener("PROXY", "127.0.0.1", 0, f)

    @unittest.skipUnless(os.name == "posix", "Private TCP witnesses require POSIX file permissions")
    def test_non_token_payload_cannot_appear_as_positive_evidence(self):
        f = self.base / "invalid-receipt.jsonl"
        listener = w.LabWitnessListener("DIRECT", "127.0.0.1", 0, f,
                                        duration=1, max_probes=1)
        thread = threading.Thread(target=listener.serve, daemon=True)
        thread.start()
        with socket.create_connection(("127.0.0.1", listener.bound_port), timeout=2) as sock:
            sock.sendall(b"GET /user-history HTTP/1.1\r\n")
            sock.shutdown(socket.SHUT_WR)
        thread.join(3)
        self.assertFalse(thread.is_alive())
        self.assertEqual(f.read_text(), "")

    def test_no_production_route_or_durable_client_telemetry_wiring(self):
        for file in ("mobile/ios/PacketTunnel/PacketTunnelProvider.swift",
                     "mobile/ios/App/AppViewModel.swift",
                     "mobile/ios/SharedCore/SmartRouteDryRunAudit.swift"):
            self.assertNotIn("qa_smart4_egress_witness", (ROOT / file).read_text())
        source = (ROOT / "scripts/qa_smart4_egress_witness.py").read_text()
        for forbidden in ("NetworkExtension", "UserDefaults", "Keychain", "SecItem",
                          "setTunnelNetworkSettings", "subprocess.run(", "requests.get("):
            self.assertNotIn(forbidden, source)
