"""Offline-only Smart4 rehearsal: live loopback and fail-closed adversarial cases."""
from __future__ import annotations
import contextlib
import io
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import qa_smart4_offline_harness as harness
from qa_smart4_egress_witness import InvalidWitness


class OfflineRehearsalTests(unittest.TestCase):
    @unittest.skipUnless(os.name == "posix", "Protected observer output requires POSIX")
    def test_real_independent_tcp_probes_and_trusted_scope(self):
        result = harness.rehearsal()
        self.assertEqual((result["confirmed_direct"], result["confirmed_proxy"],
                          result["confirmed_matches"]), (1, 1, 2))
        self.assertEqual(result["scope"], "synthetic_loopback_only")
        self.assertIs(result["physical_egress_verified"], False)
        self.assertIs(result["original_packettunnel_flow_verified"], False)
        self.assertEqual(result["cleanup"], "automatic")
        output = json.dumps(result, sort_keys=True)
        self.assertIsNone(re.search(r"[0-9a-f]{32}", output))
        for forbidden in ("password", "ip_address", "hostname", "127.0.0.1",
                          "credentials", "keychain", "session_path", "token"):
            self.assertNotIn(forbidden, output)

    @unittest.skipUnless(os.name == "posix", "Protected observer output requires POSIX")
    def test_intent_and_both_observer_files_are_private(self):
        actual_verify = harness.verify
        def inspect_permissions(intents, direct, proxy):
            for file in (intents, direct, proxy):
                self.assertEqual(file.stat().st_mode & 0o777, 0o600)
            return actual_verify(intents, direct, proxy)
        with mock.patch.object(harness, "verify", side_effect=inspect_permissions):
            self.assertEqual(harness.rehearsal()["confirmed_matches"], 2)

    @unittest.skipUnless(os.name == "posix", "Protected observer output requires POSIX")
    def test_direct_fail_closed_and_no_temp_files_left(self):
        real_temp = tempfile.TemporaryDirectory
        with real_temp(prefix="smart4-harness-test-root-") as root:
            def private_temp(*, prefix):
                return real_temp(prefix=prefix, dir=root)
            with mock.patch.object(harness.tempfile, "TemporaryDirectory",
                                   side_effect=private_temp), mock.patch.object(
                                       harness, "_send", return_value=False):
                with self.assertRaisesRegex(InvalidWitness, "DIRECT_ACK_MISSING"):
                    harness.rehearsal()
            self.assertEqual(list(Path(root).iterdir()), [], "test data must be removed")

    @unittest.skipUnless(os.name == "posix", "Protected observer output requires POSIX")
    def test_token_swap_cannot_be_accepted_as_other_route(self):
        real_send = harness._send
        with mock.patch.object(harness, "_send",
                               side_effect=lambda port, token, *, proxy:
                               real_send(port, "0" * 32 if not proxy else token,
                                         proxy=proxy)):
            with self.assertRaises(InvalidWitness):
                harness.rehearsal()

    def test_non_posix_refused_before_spawning_or_writing(self):
        with mock.patch.object(harness.os, "name", "nt"), mock.patch.object(
                harness, "_spawn", side_effect=AssertionError("unexpected start")):
            with self.assertRaisesRegex(InvalidWitness, "POSIX_PRIVATE_LOG_REQUIRED"):
                harness.rehearsal()

    def test_cli_failure_uses_fixed_non_sensitive_code(self):
        out, err = io.StringIO(), io.StringIO()
        with (mock.patch.object(harness, "rehearsal", side_effect=InvalidWitness(
                "DIRECT_ACK_MISSING")), contextlib.redirect_stdout(out),
                contextlib.redirect_stderr(err)):
            self.assertEqual(harness.main(), 2)
        self.assertEqual(out.getvalue(), "")
        self.assertEqual(err.getvalue(), "SMART4_OFFLINE_REJECTED DIRECT_ACK_MISSING\n")

    def test_no_device_connector_vpn_or_production_routing_dependencies(self):
        source = (ROOT / "scripts/qa_smart4_offline_harness.py").read_text()
        for forbidden in ("devicectl", "simctl", "iPhone Mirroring", "NEPacketTunnelProvider",
                          "Keychain", "UserDefaults", "setTunnelNetworkSettings",
                          "proxy_username", "proxy_password", "httpx", "requests."):
            self.assertNotIn(forbidden, source.split('def _read_ready')[1])
        self.assertIn('"127.0.0.1"', source)
        self.assertIn('original_packettunnel_flow_verified', source)
        self.assertIn('physical_egress_verified', source)
        self.assertIn('finally:\n            _stop(processes)', source)
