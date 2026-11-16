"""Dependency-free UDP echo safety checks (CI uses unittest discovery)."""
import argparse
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "mobile/ios/Tools/qa_udp_echo_witness.py"
spec = importlib.util.spec_from_file_location("qa_udp_echo_witness", SCRIPT)
assert spec is not None and spec.loader is not None
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class UDPEchoWitnessSafetyTests(unittest.TestCase):
    def test_rejects_all_non_global_or_non_ipv6_bind(self):
        for invalid in ("127.0.0.1", "::1", "::", "fe80::1234",
                        "fd00::2", "2001:db8::1",
                        "::ffff:192.168.1.1", "garbage"):
            with self.subTest(invalid=invalid):
                with self.assertRaises(argparse.ArgumentTypeError):
                    mod.valid_bind(invalid)

    def test_public_ipv6_bind_permitted(self):
        self.assertEqual(mod.valid_bind("2606:4700:4700::1111"),
                         "2606:4700:4700::1111")

    def test_token_exact_and_bounded_without_amplification(self):
        token = b"APL030-" + b"a" * 32
        self.assertEqual(len(token), 39)
        self.assertTrue(mod.accepted(token))
        for bad in (b"", token + b"x", token[:-1],
                    b"APL020-" + b"a" * 32,
                    b"APL030-" + b"G" * 32,
                    b"APL030-" + b"a" * 1000):
            with self.subTest(bad_length=len(bad)):
                self.assertFalse(mod.accepted(bad))

    def test_no_sensitive_payload_or_client_logging(self):
        source = SCRIPT.read_text()
        for unsafe in ("print(packet", "print(peer", "print(bind"):
            self.assertNotIn(unsafe, source)
        self.assertIn("server.sendto(packet, peer)", source)
        self.assertIn("server.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)", source)
        self.assertIn("deadline = time.monotonic() + lifetime", source)


if __name__ == "__main__":
    unittest.main()
